import Foundation
import CoreGraphics

/// v1.4.0：即時鏡頭翻譯的單一辨識區塊。
/// text + bounding box + 翻譯結果 三合一，直接餵給 overlay 渲染。
struct RecognizedTextRegion: Identifiable, Hashable {
    let id: UUID
    let originalText: String
    /// 翻譯結果。還在翻譯中（或翻譯失敗待重試）時為 nil，overlay 不顯示。
    var translatedText: String?
    /// Vision 座標系：normalized 0~1、原點左下。
    /// 轉成 SwiftUI overlay 座標的邏輯在 `TextOverlayView.overlayRect(...)`。
    var normalizedRect: CGRect
    let confidence: Float
    let recognizedAt: Date

    init(
        id: UUID = UUID(),
        originalText: String,
        translatedText: String? = nil,
        normalizedRect: CGRect,
        confidence: Float,
        recognizedAt: Date = Date()
    ) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.normalizedRect = normalizedRect
        self.confidence = confidence
        self.recognizedAt = recognizedAt
    }
}
