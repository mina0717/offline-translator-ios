import Foundation
import Speech
import AVFoundation

// MARK: - ─────────────────────────────────────────────────────────────
// Apple Speech framework 的真實作。
//
// 撰寫日：2026-04-20（Windows 端草稿，待 Mac + 實機驗證）
//
// 【Mac 實測檢查表】（借機日 1 第 1–2 小時）
//   □ 1. Info.plist 的 NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription
//        都有填（已在 project.yml 設定好）
//   □ 2. SFSpeechRecognizer(locale: Locale(identifier: "zh-Hant"))?.isAvailable == true
//   □ 3. SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.isAvailable == true
//        ⚠️ 注意：英文 locale 要用 "en-US"（非 "en"）較穩
//   □ 4. supportsOnDeviceRecognition == true？
//        若否：可能會用到雲端（MVP 要求「完全離線」→ 必須打開
//        request.requiresOnDeviceRecognition = true）
//   □ 5. requestAuthorization 會跳系統對話框
//   □ 6. AVAudioSession.setCategory(.record, mode: .measurement) 不報錯
//   □ 7. 長按 mic 按鈕 → 能看到 partial transcript 即時更新
//   □ 8. 鬆開按鈕 → final transcript 在 1 秒內返回
//   □ 9. 連續快速按 3 次 → 不當機、不重疊
//   □ 10. 中途被電話 / 其他 App 搶走 audio session → 錯誤處理正確
//
// 【流程】
//   startRecognition(in:) → 回傳 AsyncThrowingStream<String, Error>
//     ├─ 檢查 Speech + Microphone 權限
//     ├─ 配置 AVAudioSession (.record)
//     ├─ 開 AVAudioEngine，inputNode.installTap 餵 buffer 給 request
//     ├─ recognitionTask { result, error in }
//     │    yield result.bestTranscription.formattedString 到 continuation
//     └─ audioEngine.start()
//   stopRecognition() → request.endAudio(); 等 final; 回傳
// ─────────────────────────────────────────────────────────────

final class SpeechASRService: ASRService {

    // MARK: - Audio & Recognition state

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    /// 目前累積的最終文字（stopRecognition 時回傳）
    private var accumulatedFinalText: String = ""

    // MARK: - ASRService.startRecognition

    func startRecognition(in language: Language) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.accumulatedFinalText = ""

            Task {
                do {
                    try await self.requestPermissionsIfNeeded()
                    try self.configureAudioSession()
                    try self.startEngine(for: language)
                } catch let asrError as ASRError {
                    continuation.finish(throwing: asrError)
                } catch {
                    continuation.finish(throwing: ASRError.underlying(error))
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.teardown()
            }
        }
    }

    // MARK: - ASRService.stopRecognition

    func stopRecognition() async throws -> String {
        // 請求 recognizer 結束：先告訴 request 沒更多音訊進來，
        // 讓 recognitionTask 的最後一次 callback 把 isFinal 標成 true。
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // 等一小段時間讓 final result 返回（避免 race condition）
        // ⚠️ Mac 實測項 #8：這個 400ms 可能要調整
        try? await Task.sleep(nanoseconds: 400_000_000)

        // 釋放資源
        task?.cancel()
        task = nil
        request = nil
        continuation?.finish()
        continuation = nil

        return accumulatedFinalText
    }

    // MARK: - ASRService.isSupported

    func isSupported(for language: Language) -> Bool {
        let locale = Self.speechLocale(for: language)
        return SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
    }

    // MARK: - Private: setup

    private func requestPermissionsIfNeeded() async throws {
        // Speech authorization
        let speechStatus: SFSpeechRecognizerAuthorizationStatus =
            await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
        guard speechStatus == .authorized else {
            throw ASRError.permissionDenied
        }

        // Microphone authorization
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            throw ASRError.permissionDenied
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw ASRError.audioEngineFailed(error)
        }
    }

    private func startEngine(for language: Language) throws {
        // 1. 建 SFSpeechRecognizer
        let locale = Self.speechLocale(for: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw ASRError.notSupported
        }
        self.recognizer = recognizer

        // 2. 建 request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // **離線要求**：強制 on-device 辨識，避免打到 Apple 雲端
        // ⚠️ Mac 實測項 #4：若裝置不支援 on-device，改成 false 會讓 MVP 失去「離線」承諾
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            // 降級：記一筆 warning，讓使用者知道這個 locale 需要網路
            #if DEBUG
            print("⚠️ SFSpeechRecognizer on-device 不支援 \(locale.identifier)，將使用雲端")
            #endif
        }
        self.request = request

        // 3. 安裝 tap 到 input node
        //
        // v1.1.2 crash fix:
        // 之前直接 inputNode.installTap(...) 在 iOS 26.4.1 上會觸發
        //   AudioEngineModeBaseV3::CreateRecordingTap → EXC_CRASH (SIGABRT)
        // 因為 outputFormat(forBus:) 在 session 還沒完全 active 時回傳
        // 0-channel format，AVAudioEngine 直接 throw OC exception。
        //
        // 三道防禦：
        //   (a) 先 reset engine 並 removeTap，避免重複 install
        //   (b) 強制取 hardware input format（保證 channelCount > 0）
        //   (c) 驗證 format 合法後才 install
        let inputNode = audioEngine.inputNode

        // (a) 防禦：清掉舊 tap（如果使用者連續按錄音按鈕，第二次會 crash）
        inputNode.removeTap(onBus: 0)

        // (b) 取 hardware input format。比 outputFormat(forBus:) 更可靠 ——
        // 這個值由 AVAudioSession 直接決定，不依賴 engine 內部狀態。
        let recordingFormat: AVAudioFormat = {
            let hwFormat = inputNode.inputFormat(forBus: 0)
            if hwFormat.channelCount > 0 && hwFormat.sampleRate > 0 {
                return hwFormat
            }
            // 後備：用 AVAudioSession 的 sampleRate + 單聲道、Float32
            // 大多數 iPhone 是 48000 Hz mono
            let sr = AVAudioSession.sharedInstance().sampleRate
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sr > 0 ? sr : 48000,
                channels: 1,
                interleaved: false
            ) ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        }()

        // (c) 最終驗證
        guard recordingFormat.channelCount > 0,
              recordingFormat.sampleRate > 0 else {
            throw ASRError.audioEngineFailed(
                NSError(domain: "ASR", code: -100, userInfo: [
                    NSLocalizedDescriptionKey: "麥克風格式無效（channels=\(recordingFormat.channelCount), sr=\(recordingFormat.sampleRate)）"
                ])
            )
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        // 4. 啟動辨識 task
        self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.continuation?.yield(text)
                if result.isFinal {
                    self.accumulatedFinalText = text
                }
            }

            if let error {
                self.continuation?.finish(throwing: ASRError.underlying(error))
                self.continuation = nil
                self.teardown()
            }
        }

        // 5. 啟動 audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw ASRError.audioEngineFailed(error)
        }
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Locale mapping

    /// Speech framework 對某些語言需要更精確的 locale：
    /// - 英文用 `en-US` 而非 `en`
    /// - 繁中用 `zh-TW`（SFSpeechRecognizer 對 `zh-Hant` 支援不穩）
    /// ⚠️ Mac 實測項 #3：借機時驗證這兩個 locale 的 isAvailable
    private static func speechLocale(for language: Language) -> Locale {
        switch language {
        case .traditionalChinese: return Locale(identifier: "zh-TW")
        case .english:            return Locale(identifier: "en-US")
        case .turkish:            return Locale(identifier: "tr-TR")
        }
    }
}
