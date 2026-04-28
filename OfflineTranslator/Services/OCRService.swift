import Foundation
import UIKit

/// v1.2.4：拍照翻譯（Google Lens 風格）的最小單位。
/// 每個 region 是一塊 OCR 偵測到的文字 + 它在原圖上的位置 + 信心度 + 譯文。
struct OCRRegion: Identifiable, Hashable {
    /// 唯一 id，UI 用來 ForEach 識別
    let id: UUID
    /// OCR 原始偵測到的文字
    let text: String
    /// 在原圖中的歸一化 bounding box（0-1，origin 為左上角，UIKit 座標）
    let boundingBox: CGRect
    /// VNRecognizedText.confidence（0-1）；< 0.4 通常是亂讀
    let confidence: Float
    /// 翻譯成 target 語言的譯文。尚未翻譯時為 nil。
    var translatedText: String?

    init(
        id: UUID = UUID(),
        text: String,
        boundingBox: CGRect,
        confidence: Float,
        translatedText: String? = nil
    ) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.translatedText = translatedText
    }
}

/// 圖片文字辨識（OCR）服務介面。
protocol OCRService {
    /// 對輸入圖片執行 OCR，回傳偵測到的文字行陣列。
    /// - Parameters:
    ///   - image: 拍照或從相簿挑選的圖片
    ///   - language: 提示辨識器主要語言（影響準確度）
    func recognize(image: UIImage, language: Language) async throws -> [String]

    /// v1.2.4：對輸入圖片做 OCR，回傳每塊文字的 bounding box，供 UI 疊圖呈現。
    /// 失敗條件與 `recognize(image:language:)` 相同。
    func recognizeRegions(image: UIImage, language: Language) async throws -> [OCRRegion]
}

enum OCRError: LocalizedError {
    case invalidImage
    case noTextFound
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .invalidImage:      return "無法處理這張圖片，請重新拍照。"
        case .noTextFound:       return "圖片中找不到可辨識的文字。"
        case .underlying(let e): return e.localizedDescription
        }
    }
}
