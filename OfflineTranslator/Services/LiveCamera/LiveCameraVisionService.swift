import Foundation
import AVFoundation
import Vision
import CoreGraphics

/// v1.4.0：即時鏡頭翻譯真實作。
///
/// Pipeline：
///   AVCaptureSession(720p) → video queue 每幀
///     → FrameThrottler 節流到 ~5fps
///     → VNRecognizeTextRequest(.fast, 含 boundingBox)
///     → hop 到 MainActor
///     → IoU 比對舊 region + EMA 平滑座標（防抖動）
///     → 查快取 / 序列呼叫 MTService 翻譯
///     → emit 到 regionStream
///
/// **翻譯必須序列執行**：`AppleTranslationBridge` 一次只持有一個 continuation，
/// 併發呼叫會讓前一個請求收到 CancellationError。所以這裡用 `isTranslating` 閘門，
/// 翻譯中抵達的新影格直接丟棄（下一輪節流會補上）。
@MainActor
final class LiveCameraVisionService: NSObject, LiveCameraTranslationService {

    // MARK: - Public

    nonisolated var captureSession: AVCaptureSession? { session }

    let regionStream: AsyncStream<[RecognizedTextRegion]>

    // MARK: - Capture

    private nonisolated let session = AVCaptureSession()
    private nonisolated let videoOutput = AVCaptureVideoDataOutput()
    /// **只**用來送 sample buffer 給 delegate。
    private nonisolated let videoQueue = DispatchQueue(
        label: "com.mina0717.offlinetranslator.live-camera.video",
        qos: .userInitiated
    )
    /// v1.4.0 hotfix：session 的設定 / start / stop 一律走這條，**不能跟 videoQueue 共用**。
    /// 共用會造成 `startRunning()` 與 sample buffer 交付互卡（Apple AVCam 範例也是分兩條）。
    /// 同時所有 session 操作都不能在 main thread 上跑，否則 UI 會凍住。
    private nonisolated let sessionQueue = DispatchQueue(
        label: "com.mina0717.offlinetranslator.live-camera.session"
    )
    /// 只在 sessionQueue 上讀寫
    private nonisolated let configuredFlag = ConfiguredFlag()
    private nonisolated let throttler = FrameThrottler(targetFPS: 5, throttledFPS: 2)
    /// 跨執行緒共享的設定（video queue 讀、MainActor 寫）
    private nonisolated let shared = SharedConfig()

    // MARK: - Translation (MainActor only)

    private let mtService: MTService
    private var currentPair: LanguagePair
    private var cache = TranslationCache(capacity: 120)
    /// 上一輪的 region，用來做 IoU 比對 + 位置平滑
    private var previousRegions: [RecognizedTextRegion] = []
    /// 序列閘門：翻譯進行中時丟棄新影格
    private var isTranslating = false

    private let continuation: AsyncStream<[RecognizedTextRegion]>.Continuation

    // MARK: - Init

    init(mtService: MTService,
         initialPair: LanguagePair = .init(source: .english, target: .traditionalChinese)) {
        self.mtService = mtService
        self.currentPair = initialPair

        var cont: AsyncStream<[RecognizedTextRegion]>.Continuation!
        self.regionStream = AsyncStream { cont = $0 }
        self.continuation = cont

        super.init()
        shared.setRecognitionLanguages(Self.recognitionLanguages(for: initialPair.source))
    }

    // MARK: - LiveCameraTranslationService

    func start() async throws {
        guard !session.isRunning else { return }

        // v1.4.0 hotfix：設定 + startRunning **全部**在 sessionQueue 上做。
        // 之前 configureSession 跑在 MainActor，`commitConfiguration()` 會把主執行緒卡住，
        // 畫面就凍在「翻譯引擎啟動中」。
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureSessionOnSessionQueue()
                    if !session.isRunning { session.startRunning() }
                    c.resume()
                } catch {
                    c.resume(throwing: error)
                }
            }
        }

        // 進場先 preheat 當前語言對，避免第一次翻譯卡在語言包下載。
        // 一定要 detached 且不能讓它擋住 start()，因為 bridge 可能等不到 View 的 translationTask。
        let pair = currentPair
        Task.detached { [mtService] in
            await Self.preheat(pair: pair, mtService: mtService)
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        previousRegions = []
        continuation.yield([])
    }

    func setLanguagePair(_ pair: LanguagePair) async {
        guard pair != currentPair else { return }
        currentPair = pair
        cache.removeAll()
        previousRegions = []
        throttler.reset()
        shared.setRecognitionLanguages(Self.recognitionLanguages(for: pair.source))
        continuation.yield([])

        let target = pair
        Task.detached { [mtService] in
            await Self.preheat(pair: target, mtService: mtService)
        }
    }

    func setPaused(_ paused: Bool) {
        shared.setPaused(paused)
    }

    nonisolated func setThermallyThrottled(_ throttled: Bool) {
        throttler.setThermallyThrottled(throttled)
    }

    // MARK: - Session configuration

    /// **必須在 sessionQueue 上呼叫**（不是 MainActor）。
    private nonisolated func configureSessionOnSessionQueue() throws {
        guard !configuredFlag.isConfigured else { return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw LiveCameraError.cameraUnavailable
        }

        session.beginConfiguration()
        // 720p 就夠 OCR 用，省電且降低發熱（v1.2.0 設計文件的決定）
        session.sessionPreset = .hd1280x720

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw LiveCameraError.configurationFailed("cannot add camera input")
            }
            session.addInput(input)
        } catch let error as LiveCameraError {
            throw error
        } catch {
            session.commitConfiguration()
            throw LiveCameraError.configurationFailed(error.localizedDescription)
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw LiveCameraError.configurationFailed("cannot add video output")
        }
        session.addOutput(videoOutput)
        session.commitConfiguration()

        configuredFlag.markConfigured()
    }

    // MARK: - Helpers

    /// 沿用 `VisionOCRService` 的對照邏輯（那邊是 private，這裡獨立一份避免動到既有檔案）。
    private static func recognitionLanguages(for language: Language) -> [String] {
        switch language {
        case .traditionalChinese: return ["zh-Hant", "en-US"]
        case .english:            return ["en-US", "zh-Hant"]
        case .turkish:            return ["en-US"]
        case .japanese:           return ["ja-JP", "en-US"]
        case .korean:             return ["ko-KR", "en-US"]
        case .german:             return ["de-DE", "en-US"]
        case .french:             return ["fr-FR", "en-US"]
        case .spanish:            return ["es-ES", "en-US"]
        case .thai:               return ["th-TH", "en-US"]
        case .vietnamese:         return ["vi-VN", "en-US"]
        case .portuguese:         return ["pt-BR", "en-US"]
        case .italian:            return ["it-IT", "en-US"]
        case .indonesian:         return ["id-ID", "en-US"]
        case .dutch:              return ["nl-NL", "en-US"]
        }
    }

    private static func preheat(pair: LanguagePair, mtService: MTService) async {
        guard pair.isSupported else { return }
        do {
            let status = try await mtService.languagePackStatus(for: pair)
            if status != .ready {
                try await mtService.downloadLanguagePack(for: pair)
            }
        } catch {
            #if DEBUG
            print("ℹ️ live camera preheat skipped: \(error)")
            #endif
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension LiveCameraVisionService: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard !shared.isPaused() else { return }
        guard throttler.shouldProcess() else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest()
        // 即時模式用 .fast；暫停後的高精度重掃走另一條路徑（ViewModel 觸發）
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.recognitionLanguages = shared.recognitionLanguages()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observations = request.results else { return }
        let raw: [(String, CGRect, Float)] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            // 太短或信心太低的直接丟（雜訊）
            guard text.count >= 2, candidate.confidence >= 0.3 else { return nil }
            return (text, obs.boundingBox, candidate.confidence)
        }

        guard !raw.isEmpty else { return }
        Task { @MainActor [weak self] in
            await self?.process(raw: raw)
        }
    }
}

// MARK: - MainActor pipeline

private extension LiveCameraVisionService {

    /// 翻譯 + 平滑 + emit。翻譯序列化，進行中的話直接丟棄這一輪。
    func process(raw: [(String, CGRect, Float)]) async {
        guard !isTranslating else { return }
        isTranslating = true
        defer { isTranslating = false }

        let pairAtStart = currentPair
        var output: [RecognizedTextRegion] = []

        for (text, box, confidence) in raw {
            // 位置平滑：跟上一輪 IoU > 0.7 的視為同一塊，位置做 EMA
            let smoothedBox = smoothedRect(for: box)

            if let cached = cache.value(for: text) {
                output.append(RecognizedTextRegion(
                    originalText: text,
                    translatedText: cached,
                    normalizedRect: smoothedBox,
                    confidence: confidence
                ))
                continue
            }

            // 先放沒有譯文的版本，讓 overlay 至少能標出「這裡有文字」
            var region = RecognizedTextRegion(
                originalText: text,
                translatedText: nil,
                normalizedRect: smoothedBox,
                confidence: confidence
            )

            do {
                let translated = try await mtService.translate(text: text, pair: pairAtStart)
                // 翻譯期間使用者可能換了語言 → 這批結果作廢
                guard currentPair == pairAtStart else { return }
                cache.set(translated, for: text)
                region.translatedText = translated
            } catch {
                // 單一區塊翻譯失敗不影響整批（可能是語言包還在下載）
            }
            output.append(region)
        }

        previousRegions = output
        continuation.yield(output)
    }

    /// IoU > 0.7 視為同一個區塊，位置用 EMA 平滑（0.7 舊 + 0.3 新）避免抖動。
    func smoothedRect(for newBox: CGRect) -> CGRect {
        guard let match = previousRegions
            .map({ ($0, Self.iou($0.normalizedRect, newBox)) })
            .filter({ $0.1 > 0.7 })
            .max(by: { $0.1 < $1.1 })?.0
        else {
            return newBox
        }
        let old = match.normalizedRect
        let a: CGFloat = 0.7
        return CGRect(
            x: old.origin.x * a + newBox.origin.x * (1 - a),
            y: old.origin.y * a + newBox.origin.y * (1 - a),
            width: old.width * a + newBox.width * (1 - a),
            height: old.height * a + newBox.height * (1 - a)
        )
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        guard unionArea > 0 else { return 0 }
        return interArea / unionArea
    }
}

/// session 是否已設定過。只在 sessionQueue 上動，但用 lock 保守處理。
private final class ConfiguredFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isConfigured: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func markConfigured() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
}

// MARK: - Thread-safe shared config

/// video queue 與 MainActor 之間共享的少量設定。
private final class SharedConfig: @unchecked Sendable {
    private let lock = NSLock()
    private var languages: [String] = ["en-US"]
    private var paused = false

    func setRecognitionLanguages(_ langs: [String]) {
        lock.lock(); defer { lock.unlock() }
        languages = langs
    }

    func recognitionLanguages() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return languages
    }

    func setPaused(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        paused = value
    }

    func isPaused() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return paused
    }
}

// MARK: - LRU translation cache

/// 鏡頭抖動會讓同一段文字在連續影格重複出現，快取避免重複送翻譯。
struct TranslationCache {
    private var storage: [String: String] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    mutating func value(for key: String) -> String? {
        guard let hit = storage[key] else { return nil }
        // 命中就移到最新
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        return hit
    }

    mutating func set(_ value: String, for key: String) {
        if storage[key] == nil, order.count >= capacity, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
        storage[key] = value
        if let idx = order.firstIndex(of: key) { order.remove(at: idx) }
        order.append(key)
    }

    mutating func removeAll() {
        storage.removeAll()
        order.removeAll()
    }
}
