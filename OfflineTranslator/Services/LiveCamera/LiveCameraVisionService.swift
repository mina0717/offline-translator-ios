import Foundation
import AVFoundation
import Vision
import CoreGraphics
import CoreImage
import UIKit

/// v1.4.0：即時鏡頭翻譯真實作。
///
/// Pipeline：
///   AVCaptureSession(720p) → video queue 每幀
///     → FrameThrottler 節流到 ~3fps
///     → VNRecognizeTextRequest(.accurate, 含 boundingBox)
///     → OCRTextQuality 濾掉亂碼（信心 + 字面結構）
///     → hop 到 MainActor
///     → IoU 比對併進 tracked（穩定 id + EMA 位置 + 文字採信門檻）
///     → 查快取 / 序列呼叫 MTService 翻譯
///     → emit 到 regionStream
///
/// v1.4.0 hotfix4：加入跨影格追蹤（`TrackedRegion`）。核心是「畫面上的文字要有黏性」——
/// OCR 每幀都會抖，若每幀都重建 region、每幀都改文字，畫面就會像 QA 影片那樣快速亂跳。
///
/// **翻譯必須序列執行**：`AppleTranslationBridge` 一次只持有一個 continuation，
/// 併發呼叫會讓前一個請求收到 CancellationError。所以這裡用 `isTranslating` 閘門，
/// 翻譯中抵達的新影格直接丟棄（下一輪節流會補上）。
@MainActor
final class LiveCameraVisionService: NSObject, LiveCameraTranslationService {

    // MARK: - Public

    nonisolated var captureSession: AVCaptureSession? { session }

    /// v1.4.0 hotfix7：**每次 `start()` 都重建**這條 stream。
    ///
    /// `AsyncStream` 是單消費者：第一個 ViewModel `for await` 消費掉它之後，
    /// 這個 service 是共享單例（見 `AppDependencies`），下次進場的新 ViewModel
    /// 對同一條已結束的 stream 再 `for await`，一個 element 都收不到 ——
    /// 相機正常、OCR 正常，但譯文永遠出不來。這正是「跳回主畫面再進來就翻不出來」的成因。
    var regionStream: AsyncStream<[RecognizedTextRegion]> { activeStream }
    private var activeStream: AsyncStream<[RecognizedTextRegion]>!

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
    /// v1.4.0 hotfix6：等待快門的請求。下一張抵達的影格就拿去交差。
    private nonisolated let stillBox = StillRequestBox()
    /// CIContext 建立成本高，共用一個（`createCGImage` 本身是 thread-safe）
    private nonisolated static let ciContext = CIContext()
    /// v1.4.0 hotfix4：5fps + `.fast` 對著螢幕小字會辨識出大量亂碼。
    /// 改成 3fps + `.accurate` —— 翻譯目標本來就是靜止的（菜單、路牌、螢幕），
    /// 少而正確遠比多而錯亂好讀。
    private nonisolated let throttler = FrameThrottler(targetFPS: 3, throttledFPS: 1.5)
    /// 跨執行緒共享的設定（video queue 讀、MainActor 寫）
    private nonisolated let shared = SharedConfig()

    // MARK: - Translation (MainActor only)

    private let mtService: MTService
    private var currentPair: LanguagePair
    private var cache = TranslationCache(capacity: 120)
    /// v1.4.0 hotfix4：跨影格追蹤中的文字區塊。取代原本的 `previousRegions`。
    private var tracked: [TrackedRegion] = []
    /// 序列閘門：翻譯進行中時丟棄新影格
    private var isTranslating = false

    private var continuation: AsyncStream<[RecognizedTextRegion]>.Continuation?

    // MARK: - Init

    init(mtService: MTService,
         initialPair: LanguagePair = .init(source: .english, target: .traditionalChinese)) {
        self.mtService = mtService
        self.currentPair = initialPair

        var cont: AsyncStream<[RecognizedTextRegion]>.Continuation!
        self.activeStream = AsyncStream { cont = $0 }
        self.continuation = cont

        super.init()
        shared.setRecognitionLanguages(Self.recognitionLanguages(for: initialPair.source))
    }

    /// 重建 region stream + 清掉上一輪的追蹤狀態。每次 `start()` 呼叫。
    private func rearmStream() {
        continuation?.finish()
        var cont: AsyncStream<[RecognizedTextRegion]>.Continuation!
        activeStream = AsyncStream { cont = $0 }
        continuation = cont
        tracked = []
        isTranslating = false
    }

    // MARK: - LiveCameraTranslationService

    func start() async throws {
        // hotfix7：每次進場都重建 stream（單消費者，共享單例，不重建就收不到 region）。
        // 放在最前面、且不被 session.isRunning 的 guard 擋掉。
        rearmStream()

        // v1.4.0 hotfix：設定 + startRunning **全部**在 sessionQueue 上做。
        // 之前 configureSession 跑在 MainActor，`commitConfiguration()` 會把主執行緒卡住，
        // 畫面就凍在「翻譯引擎啟動中」。
        // sessionQueue 是序列的：上一輪 onDisappear 的 stopRunning() 會排在這之前，
        // 這裡的 `if !session.isRunning` 再把它重新開起來，所以快速 re-entry 也安全。
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

    /// v1.4.0 hotfix6：快門。
    ///
    /// 流程：跟 video queue 要下一張影格 → 轉成 CGImage → 用**更寬鬆的最小字高 + .accurate**
    /// 重新辨識 → 把整批文字**全部**翻完（不像即時模式有單輪上限）→ 回傳凍結畫面。
    ///
    /// 沿用與即時預覽相同的方向（`.right`）與 720p 長寬比，
    /// 疊層座標因此可以完全共用 `TextOverlayView.overlayRect`，不需要另一套幾何。
    func captureStill() async throws -> StillCapture {
        guard session.isRunning else { throw LiveCameraError.cameraUnavailable }

        let cgImage = try await withCheckedThrowingContinuation { (c: CheckedContinuation<CGImage, Error>) in
            stillBox.set(c)
        }

        // 拍照期間把即時管線的閘門關上，避免兩邊搶同一個翻譯 bridge
        isTranslating = true
        defer { isTranslating = false }

        let pairAtStart = currentPair
        // `.accurate` 辨識一張 720p 可能要 0.5～2 秒。
        // **絕對不能**在 MainActor 上跑 —— 這個功能已經因為卡主執行緒栽過兩次。
        let languages = shared.recognitionLanguages()
        let raw = await Task.detached(priority: .userInitiated) {
            Self.recognizeForStill(cgImage: cgImage, languages: languages)
        }.value

        var regions: [RecognizedTextRegion] = []
        regions.reserveCapacity(raw.count)
        for (text, box, confidence) in raw {
            let key = OCRTextQuality.cacheKey(text)
            var region = RecognizedTextRegion(
                originalText: text,
                translatedText: cache.value(for: key),
                normalizedRect: box,
                confidence: confidence
            )
            if region.translatedText == nil {
                if let translated = try? await translateWithTimeout(text: text, pair: pairAtStart) {
                    cache.set(translated, for: key)
                    region.translatedText = translated
                }
            }
            regions.append(region)
        }

        return StillCapture(
            image: UIImage(cgImage: cgImage, scale: 1, orientation: .right),
            regions: regions
        )
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        stillBox.cancel()
        tracked = []
        continuation?.yield([])
    }

    func setLanguagePair(_ pair: LanguagePair) async {
        guard pair != currentPair else { return }
        currentPair = pair
        cache.removeAll()
        tracked = []
        throttler.reset()
        shared.setRecognitionLanguages(Self.recognitionLanguages(for: pair.source))
        continuation?.yield([])

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

    /// CVPixelBuffer → CGImage（快門用）
    private nonisolated static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(ci, from: ci.extent)
    }

    /// 快門專用的辨識：沒有時間壓力，所以比即時模式更講究。
    /// - 最小字高放寬到 0.008（即時是 0.015），小字也讀得到
    /// - 一樣走 `OCRTextQuality` 擋亂碼，避免快門結果又出現亂碼黑框
    private nonisolated static func recognizeForStill(
        cgImage: CGImage,
        languages: [String]
    ) -> [(String, CGRect, Float)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.008
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .right, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return [] }

        return observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate.confidence >= OCRTextQuality.minConfidence,
                  OCRTextQuality.looksLikeRealText(text) else { return nil }
            return (text, obs.boundingBox, candidate.confidence)
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
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // v1.4.0 hotfix6：快門優先，且**放在暫停判斷之前** —— 凍結狀態下也要拍得到。
        if let pending = stillBox.take() {
            if let cg = Self.cgImage(from: pixelBuffer) {
                pending.resume(returning: cg)
            } else {
                pending.resume(throwing: LiveCameraError.configurationFailed("still capture failed"))
            }
            return
        }

        guard !shared.isPaused() else { return }
        guard throttler.shouldProcess() else { return }

        let request = VNRecognizeTextRequest()
        // v1.4.0 hotfix4：`.fast` 對小字（螢幕、密集排版）會辨識出大量亂碼，
        // 那些亂碼會被原封不動送進翻譯，再以大黑框蓋在畫面上。改用 `.accurate`。
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = OCRTextQuality.minTextHeight
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
            guard candidate.confidence >= OCRTextQuality.minConfidence else { return nil }
            // 信心值擋不住亂碼（Vision 對亂碼常給高分），再過一層字面結構檢查
            guard OCRTextQuality.looksLikeRealText(text) else { return nil }
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

    /// 一次 pass 最多送幾筆翻譯。超過的留到下一輪，避免單輪拖太久把畫面卡住。
    static var maxTranslationsPerPass: Int { 6 }
    /// 單筆翻譯逾時。bridge 只有一個 continuation，萬一 `.translationTask` 沒回應，
    /// 沒有逾時就會讓 `isTranslating` 永遠是 true —— 整條 pipeline 從此再也不動。
    static var translateTimeoutSeconds: UInt64 { 6 }

    /// 認定「同一塊文字」的 IoU 門檻。比舊的 0.7 寬鬆，因為手持鏡頭會晃。
    static var matchIoU: CGFloat { 0.3 }
    /// v1.4.0 hotfix8：幾何比對失敗時的**文字救援比對**距離上限（normalized 座標）。
    ///
    /// 手震或 Vision 重新切行會讓 IoU 掉到門檻以下，原本就會「另開一個新區塊」——
    /// 新區塊 = 新 UUID = SwiftUI 整個 view 重建 = 畫面跳，
    /// 而且新區塊完全繞過了 textCommitHits / minTextHoldSeconds 這些防抖機制。
    /// 所以只要文字一樣、位置沒差太多，就認定是同一塊，沿用原本的 id。
    static var textMatchMaxDistance: CGFloat { 0.18 }
    /// v1.4.0 hotfix8：新區塊要被看到幾次才准上畫面。
    /// 只出現一兩幀的雜訊區塊因此永遠不會閃到使用者眼前。
    static var minHitsToDisplay: Int { 2 }
    /// 記憶體裡最多保留幾個追蹤區塊（顯示上限另計）。
    static var maxTrackedRegions: Int { 40 }
    /// 新的原文要連續被辨識到幾次才換掉畫面上的舊文字。
    /// 這是止住「文字快速亂跳」的關鍵 —— OCR 每幀都會抖一點，
    /// 不設這道門檻的話畫面就會跟著每幀重寫一次。
    static var textCommitHits: Int { 3 }
    /// v1.4.0 hotfix5：換過文字之後，**至少**要維持這麼久才允許再換。
    ///
    /// 對著小字／傾斜／模糊的目標，OCR 每次讀出來都可能不一樣，
    /// 光靠「連續 N 次」擋不住（讀 A,A 換成 A，再讀 B,B 又換成 B）。
    /// 這道冷卻時間保證畫面上的字不會每秒換好幾輪 —— 這是「絲滑」的關鍵。
    static var minTextHoldSeconds: TimeInterval { 1.2 }
    /// 區塊消失後還保留多久。避免 Vision 漏掉一幀就整塊閃爍。
    /// hotfix8：0.5 → 1.5。實際辨識速率約 1～3fps，0.5 秒等於只容忍漏掉一幀；
    /// Vision 一漏辨識，區塊就死掉、下一幀又以新 id 重生 —— 這正是畫面在跳的主因之一。
    static var regionTTL: TimeInterval { 1.5 }
    /// v1.4.0 hotfix5：兩個區塊重疊超過這個比例，視為重複，只留一個。
    /// 沒有這道 NMS，鏡頭一晃就會在同一行文字上疊出好幾個黑框（QA 影片的「互相交疊」）。
    static var overlapSuppressionIoU: CGFloat { 0.25 }
    /// 同時最多顯示幾個區塊。太多會讓畫面變成一片黑框。
    static var maxDisplayedRegions: Int { 14 }
    /// 區塊出生後多久還沒譯文，才顯示等待中的虛線框。
    /// 太快顯示會讓畫面在「虛線框 → 譯文」之間閃爍。
    static var pendingIndicatorDelay: TimeInterval { 0.6 }
    /// 位置 EMA 係數（保留多少舊位置）。hotfix5：0.6 → 0.7，再穩一點。
    static var positionSmoothing: CGFloat { 0.7 }

    /// 追蹤 + 翻譯 + emit。翻譯序列化，進行中的話直接丟棄這一輪。
    func process(raw: [(String, CGRect, Float)]) async {
        guard !isTranslating else { return }
        isTranslating = true
        defer { isTranslating = false }

        let pairAtStart = currentPair
        let now = Date()

        // 1. 把這一幀的辨識結果併進 tracked（比對既有區塊，而不是全部重建）
        var matchedIndices = Set<Int>()
        for (text, box, confidence) in raw {
            if let idx = bestMatchIndex(for: box, text: text, excluding: matchedIndices) {
                matchedIndices.insert(idx)
                merge(text: text, box: box, confidence: confidence, into: idx, now: now)
            } else {
                let cached = cache.value(for: OCRTextQuality.cacheKey(text))
                tracked.append(TrackedRegion(
                    id: UUID(),
                    bornAt: now,
                    text: text,
                    translated: cached,
                    translatedFor: cached == nil ? nil : text,
                    rect: box,
                    confidence: confidence,
                    candidate: nil,
                    candidateHits: 0,
                    hits: 1,
                    lastSeen: now,
                    committedAt: now
                ))
            }
        }

        // 2. 太久沒再被看到的區塊才移除（不是漏一幀就刪，那會閃爍）
        tracked.removeAll { now.timeIntervalSince($0.lastSeen) > Self.regionTTL }
        // 3. 去掉互相重疊的重複框
        suppressOverlaps()
        // 4. 記憶體上限（顯示上限在 emit 時才套用）。
        //    hotfix8：這裡**不能**用顯示上限去砍 tracked ——
        //    砍掉等於毀掉那塊的 id 與譯文，下次又以新 id 重生，畫面就跳。
        if tracked.count > Self.maxTrackedRegions {
            tracked = Array(
                tracked.sorted { $0.lastSeen > $1.lastSeen }.prefix(Self.maxTrackedRegions)
            )
        }
        emit(now: now)

        // 5. 逐一補譯文（譯文過時或從未翻過的），每翻好一筆就再 emit 一次
        let pendingIDs = tracked.filter { !$0.isTranslationCurrent }
            .prefix(Self.maxTranslationsPerPass)
            .map(\.id)

        for regionID in pendingIDs {
            guard let idx = tracked.firstIndex(where: { $0.id == regionID }) else { continue }
            let text = tracked[idx].text
            do {
                let translated = try await translateWithTimeout(text: text, pair: pairAtStart)
                // 翻譯期間使用者可能換了語言 → 這批結果作廢
                guard currentPair == pairAtStart else { return }
                cache.set(translated, for: OCRTextQuality.cacheKey(text))
                // await 期間 tracked 可能已經變動，用 id 重新定位；
                // 而且要確認原文還是當初送翻的那段（可能又 commit 了新的）
                guard let current = tracked.firstIndex(where: { $0.id == regionID }),
                      tracked[current].text == text else { continue }
                tracked[current].translated = translated
                tracked[current].translatedFor = text
                emit(now: Date())
            } catch {
                #if DEBUG
                print("ℹ️ live camera translate failed: \(error)")
                #endif
            }
        }
    }

    /// 把新的辨識結果併進既有區塊。
    ///
    /// 重點在於**譯文有黏性**：位置立刻跟上，但畫面上的文字不會因為 OCR 抖了一下就換掉。
    /// 新原文必須連續出現 `textCommitHits` 次才會被採信，
    /// 而且在新譯文回來之前，舊譯文會繼續留在畫面上（不會退回虛線框）。
    func merge(text: String, box: CGRect, confidence: Float, into idx: Int, now: Date) {
        tracked[idx].rect = Self.smoothed(old: tracked[idx].rect, new: box)
        tracked[idx].lastSeen = now
        tracked[idx].confidence = confidence
        tracked[idx].hits += 1

        // v1.4.0 hotfix5：用正規化後的鍵比對「是不是同一句」。
        // OCR 在連續影格常常只差一個標點或大小寫（`QA testing` / `QA testing.`），
        // 用原字串比會把這種抖動當成「換了新句子」，畫面就跟著閃。
        let key = OCRTextQuality.cacheKey(text)
        if key == OCRTextQuality.cacheKey(tracked[idx].text) {
            tracked[idx].candidate = nil
            tracked[idx].candidateHits = 0
            return
        }

        if let candidate = tracked[idx].candidate, key == OCRTextQuality.cacheKey(candidate) {
            tracked[idx].candidateHits += 1
            // 用最新一次的讀法（通常標點比較完整）
            tracked[idx].candidate = text
        } else {
            tracked[idx].candidate = text
            tracked[idx].candidateHits = 1
        }

        guard tracked[idx].candidateHits >= Self.textCommitHits else { return }
        // 冷卻時間內不換字，避免畫面每秒重寫好幾次
        guard now.timeIntervalSince(tracked[idx].committedAt) >= Self.minTextHoldSeconds else { return }

        // 連續看到同一個新原文、且已過冷卻 → 採信
        tracked[idx].text = text
        tracked[idx].candidate = nil
        tracked[idx].candidateHits = 0
        tracked[idx].committedAt = now
        if let cached = cache.value(for: key) {
            // 快取命中，直接換成對應的新譯文
            tracked[idx].translated = cached
            tracked[idx].translatedFor = text
        }
        // 沒命中就**保留舊譯文顯示**，只是 translatedFor 已不等於 text，
        // 下一步 process() 會把它排進重譯佇列。畫面因此不會閃成空白／虛線框。
    }

    /// v1.4.0 hotfix5：重疊抑制（NMS）。
    ///
    /// 鏡頭晃動時，同一行文字的新 observation 可能與既有區塊 IoU 不夠高而另開一個區塊，
    /// 於是同一行上疊了兩三個黑框 —— 這是 QA 影片裡「互相交疊」的直接成因。
    ///
    /// 保留策略：**已經穩定顯示中的優先**，其次才看誰先出現。
    /// hotfix8：原本只看 bornAt，會讓「剛冒出來的雜訊框」有機會擠掉
    /// 已經在畫面上待很久的框（只要它更早生成），畫面因此會抽動。
    func suppressOverlaps() {
        guard tracked.count > 1 else { return }
        let ordered = tracked.enumerated().sorted { lhs, rhs in
            let lStable = lhs.element.hits >= Self.minHitsToDisplay
            let rStable = rhs.element.hits >= Self.minHitsToDisplay
            if lStable != rStable { return lStable }
            return lhs.element.bornAt < rhs.element.bornAt
        }
        var keptRects: [CGRect] = []
        var keptIndices = Set<Int>()
        for (index, region) in ordered {
            let clashes = keptRects.contains { Self.iou($0, region.rect) > Self.overlapSuppressionIoU }
            if !clashes {
                keptRects.append(region.rect)
                keptIndices.insert(index)
            }
        }
        guard keptIndices.count < tracked.count else { return }
        tracked = tracked.enumerated()
            .filter { keptIndices.contains($0.offset) }
            .map(\.element)
    }

    func emit(now: Date) {
        // hotfix8：只有「被看到夠多次」的區塊才上畫面。
        // 只出現一兩幀的雜訊區塊因此永遠不會閃到使用者眼前 —— 這是止跳的關鍵之一。
        // 顯示上限也在這裡才套用（不動 tracked 本身，才不會毀掉 id 與譯文）。
        let regions = tracked
            .filter { $0.hits >= Self.minHitsToDisplay }
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(Self.maxDisplayedRegions)
            .map { t in
                RecognizedTextRegion(
                    id: t.id,
                    originalText: t.text,
                    translatedText: t.translated,
                    normalizedRect: t.rect,
                    confidence: t.confidence,
                    recognizedAt: t.bornAt,
                    showsPendingIndicator: t.translated == nil
                        && now.timeIntervalSince(t.bornAt) > Self.pendingIndicatorDelay
                )
            }
        continuation?.yield(Array(regions))
    }

    /// 找出與這個 observation 最相符的既有區塊。
    ///
    /// 兩段式：
    /// 1. **幾何**：IoU 超過門檻的取最高分
    /// 2. **文字救援**：幾何失敗時，只要正規化後的文字一樣、而且中心點沒跑太遠，
    ///    就認定是同一塊。手震與 Vision 重新切行都會讓 IoU 掉下來，
    ///    沒有這段就會不斷「殺掉舊區塊、生出新 id」→ 畫面跳。
    func bestMatchIndex(for box: CGRect, text: String, excluding used: Set<Int>) -> Int? {
        var bestGeometry: (index: Int, score: CGFloat)?
        for i in tracked.indices where !used.contains(i) {
            let score = Self.iou(tracked[i].rect, box)
            guard score > Self.matchIoU else { continue }
            if bestGeometry == nil || score > bestGeometry!.score { bestGeometry = (i, score) }
        }
        if let hit = bestGeometry { return hit.index }

        let key = OCRTextQuality.cacheKey(text)
        var bestText: (index: Int, distance: CGFloat)?
        for i in tracked.indices where !used.contains(i) {
            let sameAsCommitted = OCRTextQuality.cacheKey(tracked[i].text) == key
            let sameAsCandidate = tracked[i].candidate.map { OCRTextQuality.cacheKey($0) == key } ?? false
            guard sameAsCommitted || sameAsCandidate else { continue }
            let distance = Self.centerDistance(tracked[i].rect, box)
            guard distance < Self.textMatchMaxDistance else { continue }
            if bestText == nil || distance < bestText!.distance { bestText = (i, distance) }
        }
        return bestText?.index
    }

    static func centerDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 加逾時的翻譯。逾時後留下的懸空 continuation 會被 bridge 的下一筆請求
    /// 以 CancellationError 收掉，不會累積。
    func translateWithTimeout(text: String, pair: LanguagePair) async throws -> String {
        let service = mtService
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { @MainActor in
                try await service.translate(text: text, pair: pair)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.translateTimeoutSeconds * 1_000_000_000)
                throw LiveCameraError.translateTimeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw LiveCameraError.translateTimeout
            }
            return first
        }
    }

    /// 位置 EMA 平滑，避免手震讓黑框抖動
    static func smoothed(old: CGRect, new: CGRect) -> CGRect {
        let a = positionSmoothing
        return CGRect(
            x: old.origin.x * a + new.origin.x * (1 - a),
            y: old.origin.y * a + new.origin.y * (1 - a),
            width: old.width * a + new.width * (1 - a),
            height: old.height * a + new.height * (1 - a)
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

// MARK: - Tracked region

/// v1.4.0 hotfix4：跨影格追蹤同一塊文字。
///
/// 沒有這層，每一幀都是全新的 `RecognizedTextRegion`（全新 UUID），
/// SwiftUI 的 `ForEach` 會把所有疊層整批拆掉重建 —— 位置跳、內容換、無法動畫。
/// 加上 OCR 本身每幀都會抖一點字，畫面就變成 QA 影片裡那樣完全無法閱讀。
private struct TrackedRegion {
    /// 穩定 id：跨影格不變，SwiftUI 才能認出是同一個 view 並做動畫
    let id: UUID
    let bornAt: Date
    /// 目前「已採信」並顯示中的原文
    var text: String
    /// 目前畫面上顯示的譯文（重新翻譯期間可能暫時是舊的，但不會閃成空白）
    var translated: String?
    /// `translated` 是針對哪一段原文算出來的。
    /// 用它判斷「需不需要重譯」：`translatedFor != text` 就代表原文換了、譯文過時。
    var translatedFor: String?
    var rect: CGRect
    var confidence: Float
    /// 觀察中的新原文（還沒連續出現足夠次數）
    var candidate: String?
    var candidateHits: Int
    /// 這一塊總共被辨識到幾次。太少就不上畫面（擋掉只閃一兩幀的雜訊）。
    var hits: Int
    var lastSeen: Date
    /// 顯示中的原文**最後一次被換掉**的時間。用來做換字冷卻，
    /// 避免對著模糊小字時畫面每秒重寫好幾輪。
    var committedAt: Date

    /// 譯文是否已對應到目前的原文
    var isTranslationCurrent: Bool { translatedFor == text }
}

/// v1.4.0 hotfix6：等待中的快門請求。
/// video queue 交付影格、MainActor 發起請求，兩邊都會碰，所以用 lock 保護，
/// 並保證同一個 continuation 只 resume 一次。
private final class StillRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage, Error>?

    /// 送出新請求。若前一個還在等，先用 CancellationError 收掉，避免懸空。
    func set(_ c: CheckedContinuation<CGImage, Error>) {
        lock.lock()
        let old = continuation
        continuation = c
        lock.unlock()
        old?.resume(throwing: CancellationError())
    }

    func take() -> CheckedContinuation<CGImage, Error>? {
        lock.lock(); defer { lock.unlock() }
        let c = continuation
        continuation = nil
        return c
    }

    func cancel() {
        take()?.resume(throwing: CancellationError())
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
