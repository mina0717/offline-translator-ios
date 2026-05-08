import Foundation

/// App 目前支援的語言清單。
///
/// v1.3.0：新增日／韓／德／法 4 個語言（共 7 種、42 個翻譯方向）。
/// v1.2.5：加入土耳其文（Apple Translate iOS 18.4+ 支援；Vision OCR 不支援，
/// 拍照時會嘗試以拉丁字母 fallback 辨識，不保證高準確度）。
///
/// **未支援**：克羅埃西亞文（Apple Translate 目前無此語言對）。
///
/// **SwiftData 相容性**：raw value 沿用 v1.2.x 的 case name（traditionalChinese / english / turkish），
/// 新增 case 不影響舊資料解碼。
enum Language: String, CaseIterable, Identifiable, Codable, Hashable {
    case traditionalChinese
    case english
    case turkish
    // v1.3.0 新增
    case japanese
    case korean
    case german
    case french

    var id: String { rawValue }

    /// BCP-47 語系代碼。Apple Translation / Speech / Vision 都用這個。
    /// 英文用 `en-US`：SFSpeechRecognizer 對純 `en` locale 支援不穩，必須帶 region。
    var bcp47: String {
        switch self {
        case .traditionalChinese: return "zh-Hant"
        case .english:            return "en-US"
        case .turkish:            return "tr-TR"
        case .japanese:           return "ja-JP"
        case .korean:             return "ko-KR"
        case .german:             return "de-DE"
        case .french:             return "fr-FR"
        }
    }

    /// UI 顯示名稱（採當地語慣用寫法，方便母語使用者辨識）
    var displayName: String {
        switch self {
        case .traditionalChinese: return "繁體中文"
        case .english:            return "English"
        case .turkish:            return "Türkçe"
        case .japanese:           return "日本語"
        case .korean:             return "한국어"
        case .german:             return "Deutsch"
        case .french:             return "Français"
        }
    }

    /// UI 上顯示的國旗 emoji（視覺輔助）
    var flag: String {
        switch self {
        case .traditionalChinese: return "🇹🇼"
        case .english:            return "🇺🇸"
        case .turkish:            return "🇹🇷"
        case .japanese:           return "🇯🇵"
        case .korean:             return "🇰🇷"
        case .german:             return "🇩🇪"
        case .french:             return "🇫🇷"
        }
    }

    /// 語音辨識 / TTS 用的 Locale
    var locale: Locale { Locale(identifier: bcp47) }

    /// v1.2.5：給 LanguageDetector 用 — NLLanguage rawValue 對應到 Language case
    /// v1.3.0：擴充 ja/ko/de/fr
    init?(forNLCode code: String) {
        switch code {
        case "zh-Hant", "zh-Hans", "zh": self = .traditionalChinese
        case "en":                       self = .english
        case "tr":                       self = .turkish
        case "ja":                       self = .japanese
        case "ko":                       self = .korean
        case "de":                       self = .german
        case "fr":                       self = .french
        default:                         return nil
        }
    }
}

/// 某一對語言對（source → target）。
struct LanguagePair: Hashable, Codable {
    let source: Language
    let target: Language

    /// v1.3.0：改為動態生成所有 7×6 = 42 個有效配對（排除自我翻譯）。
    /// Apple Translation Framework 在 runtime 會用 `LanguageAvailability.status(from:to:)`
    /// 確認個別配對在當前 iOS 版本是否可用；不可用會跳「語言包不可用」提示。
    /// 因此這裡列出所有理論上 Apple 支援的配對即可。
    ///
    /// 已驗證 Apple Translation Framework（iOS 17.4+ / 18+）支援的 19 種語言中，
    /// 我們的 7 種全部納入：zh-Hant / en / tr / ja / ko / de / fr
    static let supported: [LanguagePair] = {
        var pairs: [LanguagePair] = []
        for src in Language.allCases {
            for tgt in Language.allCases where src != tgt {
                pairs.append(LanguagePair(source: src, target: tgt))
            }
        }
        return pairs
    }()

    var isSupported: Bool { Self.supported.contains(self) }
}
