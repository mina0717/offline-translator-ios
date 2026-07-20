import Foundation
import AVFoundation
import CoreGraphics

/// v1.4.0：即時鏡頭翻譯的假實作。
/// 用在 SwiftUI Preview 與單元測試 —— 沒有相機，定時吐幾個假的辨識結果。
@MainActor
final class LiveCameraServiceMock: LiveCameraTranslationService {

    nonisolated var captureSession: AVCaptureSession? { nil }

    let regionStream: AsyncStream<[RecognizedTextRegion]>
    private let continuation: AsyncStream<[RecognizedTextRegion]>.Continuation

    private var tickTask: Task<Void, Never>?
    private var paused = false
    private var pair: LanguagePair = .init(source: .english, target: .traditionalChinese)

    /// 假資料：文字 + normalized rect（Vision 座標，原點左下）
    private let samples: [(String, String, CGRect)] = [
        ("Today's Special", "今日特餐", CGRect(x: 0.12, y: 0.62, width: 0.55, height: 0.07)),
        ("Grilled Salmon", "香煎鮭魚", CGRect(x: 0.14, y: 0.48, width: 0.44, height: 0.06)),
        ("No credit cards", "不接受信用卡", CGRect(x: 0.10, y: 0.30, width: 0.50, height: 0.05))
    ]

    init() {
        var cont: AsyncStream<[RecognizedTextRegion]>.Continuation!
        self.regionStream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func start() async throws {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            var visible = 1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let self, !self.paused else { continue }
                let slice = self.samples.prefix(visible).map { sample in
                    RecognizedTextRegion(
                        originalText: sample.0,
                        translatedText: sample.1,
                        normalizedRect: sample.2,
                        confidence: 0.95
                    )
                }
                self.continuation.yield(Array(slice))
                visible = visible % self.samples.count + 1
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        continuation.yield([])
    }

    func setLanguagePair(_ pair: LanguagePair) async {
        self.pair = pair
        continuation.yield([])
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
    }

    nonisolated func setThermallyThrottled(_ throttled: Bool) {
        // no-op
    }
}
