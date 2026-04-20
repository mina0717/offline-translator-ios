import Foundation
import UIKit

/// 圖片文字辨識（OCR）服務介面。
protocol OCRService {
    /// 對輸入圖片執行 OCR，回傳偵測到的文字行陣列。
    /// - Parameters:
    ///   - image: 拍照或從相簿挑選的圖片
    ///   - language: 提示辨識器主要語言（影響準確度）
    func recognize(image: UIImage, language: Language) async throws -> [String]
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
