import Foundation
import Speech
import AVFoundation

/// v1.5.0：`HandsFreeASRService` 的 Apple Speech 實作。
///
/// ## 兩個非做不可的技術重點
///
/// ### 1. 辨識任務必須輪替
/// `SFSpeechRecognitionTask` 有時間上限（約 1 分鐘）。連續聆聽如果只開一個 task，
/// 講到一半就會無聲停掉。所以**每斷一句就換一個新的 request + task**，
/// 另外加一道硬性計時器，處理「一直講不停」的情況。
///
/// 換的時候順序很重要：**先把新的裝上去，再結束舊的**。
/// 反過來做會在兩者之間漏掉音訊。
///
/// ### 2. 事件串流每次 start() 都要重建
/// `AsyncStream` 是**單消費者**：被消費過一次就結束了。
/// 這個服務是共享單例，第二次進畫面時若沿用同一條 stream，
/// 辨識照跑但事件永遠送不到 UI —— 相機翻譯就是栽在這裡（v15.6）。
@MainActor
final class SpeechHandsFreeASRService: HandsFreeASRService {

    // MARK: - Stream

    var events: AsyncStream<HandsFreeASREvent> { activeStream }
    private var activeStream: AsyncStream<HandsFreeASREvent>!
    private var continuation: AsyncStream<HandsFreeASREvent>.Continuation?

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()
    /// audio tap 執行緒與 MainActor 共用，必須加鎖
    private nonisolated let requestBox = RequestBox()
    /// **只在 audio tap 執行緒上使用**（`reset()` 例外，但那時 engine 已停）
    private nonisolated let vad = VoiceActivityDetector()
    /// 音量事件節流器，避免每個 buffer 都跳一次 MainActor
    private nonisolated let levelThrottle = LevelThrottle(everyNBuffers: 6)

    private var recognizer: SFSpeechRecognizer?
    private var currentTask: SFSpeechRecognitionTask?
    private var currentLanguage: Language = .english
    private(set) var isRunning = false

    /// 分辨「哪一輪辨識」的世代編號。
    /// 舊 task 在收尾時仍會回 callback，用這個擋掉，避免舊結果蓋掉新的一輪。
    private var generation = 0
    /// 這一輪已經吐出的最後一段 partial（斷句時當作 final 的後備）
    private var latestPartial = ""
    /// 硬性輪替計時器，處理「一直講不停」超過 task 時限的情況
    private var rotationTimer: Task<Void, Never>?
    /// 單一 task 最長存活時間，留安全邊際（Apple 上限約 60 秒）
    private static let maxTaskSeconds: UInt64 = 45

    init() {
        rearmStream()
    }

    // MARK: - Lifecycle

    func start(language: Language) async throws {
        guard !isRunning else { return }

        try await requestPermissions()

        guard supportsOnDevice(language) else {
            throw HandsFreeASRError.notSupportedOffline(language)
        }

        currentLanguage = language
        rearmStream()
        vad.reset()
        latestPartial = ""

        guard let recognizer = SFSpeechRecognizer(locale: Self.speechLocale(for: language)),
              recognizer.isAvailable else {
            throw HandsFreeASRError.notSupportedOffline(language)
        }
        self.recognizer = recognizer

        try configureAudioSession()
        try installTap()

        beginNewRecognitionRound()

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            teardownAudio()
            throw HandsFreeASRError.audioEngineFailed(error.localizedDescription)
        }

        isRunning = true
    }

    func stop() {
        isRunning = false
        rotationTimer?.cancel(); rotationTimer = nil
        generation += 1

        currentTask?.cancel()
        currentTask = nil
        requestBox.take()?.endAudio()

        teardownAudio()
        continuation?.finish()
        continuation = nil
        vad.reset()
    }

    func supportsOnDevice(_ language: Language) -> Bool {
        guard let r = SFSpeechRecognizer(locale: Self.speechLocale(for: language)) else { return false }
        return r.supportsOnDeviceRecognition
    }

    // MARK: - Stream management

    private func rearmStream() {
        continuation?.finish()
        var cont: AsyncStream<HandsFreeASREvent>.Continuation!
        activeStream = AsyncStream { cont = $0 }
        continuation = cont
    }

    // MARK: - Audio setup

    private func requestPermissions() async throws {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { throw HandsFreeASRError.permissionDenied }

        let micGranted: Bool = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard micGranted else { throw HandsFreeASRError.permissionDenied }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // 免持模式之後要朗讀譯文，所以用 .playAndRecord（純 .record 不能放音）
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw HandsFreeASRError.audioEngineFailed(error.localizedDescription)
        }
    }

    private func installTap() throws {
        let inputNode = audioEngine.inputNode
        // 沿用 v1.1.2 的 crash 防禦：先清舊 tap、強制取 hardware format、驗證後才裝
        inputNode.removeTap(onBus: 0)

        let format: AVAudioFormat = {
            let hw = inputNode.inputFormat(forBus: 0)
            if hw.channelCount > 0 && hw.sampleRate > 0 { return hw }
            let sr = AVAudioSession.sharedInstance().sampleRate
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sr > 0 ? sr : 48000,
                channels: 1,
                interleaved: false
            ) ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        }()

        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw HandsFreeASRError.audioEngineFailed(
                "麥克風格式無效（channels=\(format.channelCount), sr=\(format.sampleRate)）"
            )
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            // ⚠️ 這裡是 audio 執行緒：只做輕量工作，重活丟回 MainActor
            self.requestBox.current?.append(buffer)

            let event = self.vad.process(buffer: buffer)

            // 狀態變化才是重點，優先處理
            if event != .none {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .speechStarted: self.emit(.speechStarted)
                    case .speechEnded:   self.finalizeCurrentSegment()
                    case .none:          break
                    }
                }
                return
            }

            // 音量更新要節流。這個 closure 每秒被呼叫約 47 次
            // （48kHz ÷ 1024 frames），每次都開一個 Task 跳 MainActor
            // 會把主執行緒灌爆 —— 音量指示只是視覺效果，每秒 8 次綽綽有餘。
            guard self.levelThrottle.shouldEmit() else { return }
            let level = self.vad.currentLevelDB
            Task { @MainActor [weak self] in self?.emit(.level(level)) }
        }
    }

    private func teardownAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        requestBox.take()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recognition rounds

    /// 開一輪新的辨識（新 request + 新 task），並把它裝進 box 供 audio tap 餵資料。
    private func beginNewRecognitionRound() {
        guard let recognizer else { return }

        generation += 1
        let myGeneration = generation
        latestPartial = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 免持會連續聽很久，一定要 on-device，否則等於一直在打雲端
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // 先裝上新的，audio tap 立刻開始餵這個 request（舊的稍後才結束，不會有空窗）
        let oldRequest = requestBox.swap(to: request)

        currentTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, myGeneration == self.generation else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.commitFinal(text)
                    } else {
                        self.latestPartial = text
                        self.emit(.partial(text))
                    }
                }
                if let error, myGeneration == self.generation {
                    // 單輪失敗不該讓整個免持模式停掉，換一輪繼續
                    self.emit(.recoverableError(error.localizedDescription))
                    self.beginNewRecognitionRound()
                }
            }
        }

        // 舊的 request 收尾（放在最後，確保新的已經接手）
        oldRequest?.endAudio()

        // 硬性輪替：一直講不停也不會撞到 task 時限
        rotationTimer?.cancel()
        rotationTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.maxTaskSeconds * 1_000_000_000)
            guard let self, !Task.isCancelled, self.isRunning,
                  myGeneration == self.generation else { return }
            self.finalizeCurrentSegment()
        }
    }

    /// 一句話結束：把目前這輪收掉並開新的一輪。
    private func finalizeCurrentSegment() {
        guard isRunning else { return }
        // 這輪還沒辨識到任何東西就不用切（例如只是環境噪音觸發了 VAD）
        guard !latestPartial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // 先把 partial 當成保底結果送出，避免 isFinal 遲遲不來
        commitFinal(latestPartial)
        beginNewRecognitionRound()
    }

    private func commitFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        latestPartial = ""
        emit(.finalized(trimmed))
    }

    private func emit(_ event: HandsFreeASREvent) {
        continuation?.yield(event)
    }

    // MARK: - Locale

    private static func speechLocale(for language: Language) -> Locale {
        switch language {
        case .traditionalChinese: return Locale(identifier: "zh-TW")
        case .english:            return Locale(identifier: "en-US")
        case .japanese:           return Locale(identifier: "ja-JP")
        case .korean:             return Locale(identifier: "ko-KR")
        case .german:             return Locale(identifier: "de-DE")
        case .french:             return Locale(identifier: "fr-FR")
        case .spanish:            return Locale(identifier: "es-ES")
        case .italian:            return Locale(identifier: "it-IT")
        case .portuguese:         return Locale(identifier: "pt-BR")
        case .dutch:              return Locale(identifier: "nl-NL")
        case .turkish:            return Locale(identifier: "tr-TR")
        case .thai:               return Locale(identifier: "th-TH")
        case .vietnamese:         return Locale(identifier: "vi-VN")
        case .indonesian:         return Locale(identifier: "id-ID")
        }
    }
}

// MARK: - LevelThrottle

/// 音量事件節流。只在 audio tap 執行緒上呼叫（單一執行緒，不需鎖）。
private final class LevelThrottle: @unchecked Sendable {
    private let everyNBuffers: Int
    private var counter = 0

    init(everyNBuffers: Int) { self.everyNBuffers = max(1, everyNBuffers) }

    func shouldEmit() -> Bool {
        counter += 1
        guard counter >= everyNBuffers else { return false }
        counter = 0
        return true
    }
}

// MARK: - RequestBox

/// audio tap 執行緒與 MainActor 共用目前的辨識 request，必須加鎖。
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    var current: SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        return request
    }

    /// 換上新的，回傳舊的（呼叫端負責收尾）
    @discardableResult
    func swap(to new: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        let old = request
        request = new
        return old
    }

    @discardableResult
    func take() -> SFSpeechAudioBufferRecognitionRequest? {
        swap(to: nil)
    }
}
