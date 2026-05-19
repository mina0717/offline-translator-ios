import Foundation
import NaturalLanguage

/// 偵測一段文字的語言。
/// 使用 Apple `NaturalLanguage.NLLanguageRecognizer`（純本機、免網路、免權限）。
///
/// v13.6：擴展支援西班牙／泰／越／葡／義／印尼／荷蘭文（共 14 國）。
/// v1.3.0：擴展支援日／韓／德／法。
/// v1.2.5：加入土耳其文。
/// 範圍以外（克羅埃西亞、阿拉伯、希伯來...）回傳 nil，UI 不會自動切換。
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
        case .turkish:            return .turkish
        case .japanese:           return .japanese
        case .korean:             return .korean
        case .german:             return .german
        case .french:             return .french
        // v13.6 新增
        case .spanish:            return .spanish
        case .thai:               return .thai
        case .vietnamese:         return .vietnamese
        case .portuguese:         return .portuguese
        case .italian:            return .italian
        case .indonesian:         return .indonesian
        case .dutch:              return .dutch
        default:                  return nil
        }
    }

    /// v1.2.5：給 UI 提示用。回傳 NLLanguage 的 raw code（例如 "hr"、"ar"），
    /// 即使不在我們支援清單也回，方便顯示「偵測到 hr，但未支援」之類訊息。
    func detectRawCode(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
