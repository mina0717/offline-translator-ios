import Foundation
import NaturalLanguage

/// 偵測一段文字的語言。
/// 使用 Apple `NaturalLanguage.NLLanguageRecognizer`（純本機、免網路、免權限）。
///
/// MVP 縮減範圍後只處理繁中 / 英文；其他語言（含日文）一律回傳 nil，
/// 交由 UI 以錯誤訊息引導使用者。
struct LanguageDetector {

    /// 回傳最可能的 Language（限制在我們支援的清單內）。
    /// 若辨識不出或不在支援清單，回傳 `nil`。
    func detect(_ text: String) -> Language? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let nlLang = recognizer.dominantLanguage else { return nil }

        switch nlLang {
        case .traditionalChinese: return .traditionalChinese
        case .simplifiedChinese:  return .traditionalChinese   // 簡中暫時也走繁中路線
        case .english:            return .english
        default:                  return nil
        }
    }
}
