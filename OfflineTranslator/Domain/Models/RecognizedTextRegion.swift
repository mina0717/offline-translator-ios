import Foundation
import CoreGraphics

/// v1.4.0：即時鏡頭翻譯的單一辨識區塊。
/// text + bounding box + 翻譯結果 三合一，直接餵給 overlay 渲染。
///
/// **`id` 必須跨影格穩定**：service 端用 IoU 比對把同一塊文字對應到同一個 id，
/// SwiftUI 的 `ForEach` 才會認出是同一個 view 並做位置動畫。
/// 每幀給新 UUID 會讓所有疊層整批拆掉重建 —— 那正是 v1.4.0 QA 影片裡「文字快速亂跳」的成因。
struct RecognizedTextRegion: Identifiable, Hashable {
    let id: UUID
    let originalText: String
    /// 翻譯結果。還在翻譯中（或翻譯失敗待重試）時為 nil。
    var translatedText: String?
    /// Vision 座標系：normalized 0~1、原點左下。
    /// 轉成 SwiftUI overlay 座標的邏輯在 `TextOverlayView.overlayRect(...)`。
    var normalizedRect: CGRect
    let confidence: Float
    /// 這個區塊**第一次**被辨識到的時間（跨影格保留，不是每幀更新）
    let recognizedAt: Date
    /// 是否要畫「等待翻譯中」的虛線框。
    /// 由 service 決定：只有等超過一段時間還沒譯文才設 true，
    /// 否則每個新區塊都會先閃一下虛線框再變成譯文。
    var showsPendingIndicator: Bool

    init(
        id: UUID = UUID(),
        originalText: String,
        translatedText: String? = nil,
        normalizedRect: CGRect,
        confidence: Float,
        recognizedAt: Date = Date(),
        showsPendingIndicator: Bool = false
    ) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.normalizedRect = normalizedRect
        self.confidence = confidence
        self.recognizedAt = recognizedAt
        self.showsPendingIndicator = showsPendingIndicator
    }
}
