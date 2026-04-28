import Foundation

/// App 目前支援的語言清單。
/// v1.2.5：加入土耳其文（Apple Translate iOS 18.4+ 支援；Vision OCR 不支援，
/// 拍照時會嘗試以拉丁字母 fallback 辨識，不保證高準確度）。
///
/// 歷史：曾規劃支援日文 (ja)，因 13 天時程壓力縮減範圍。
/// **未支援**：克羅埃西亞文（Apple Translate 目前無此語言對）。
enum Language: String, CaseIterable, Identifiable, Codable, Hashable {
    case traditionalChinese
    case english
    case turkish

    var id: String { rawValue }

    /// BCP-47 語系代碼。Apple Translation / Speech / Vision 都用這個。
    /// 英文用 `en-US`：SFSpeechRecognizer 對純 `en` locale 支援不穩，必須帶 region。
    var bcp47: String {
        switch self {
        case .traditionalChinese: return "zh-Hant"
        case .english:            return "en-US"
        case .turkish:            return "tr-TR"
        }
    }

    /// UI 顯示名稱（繁中）
    var displayName: String {
        switch self {
        case .traditionalChinese: return "繁體中文"
        case .english:            return "English"
        case .turkish:            return "Türkçe"
        }
    }

    /// UI 上顯示的國旗 emoji（視覺輔助）
    var flag: String {
        switch self {
        case .traditionalChinese: return "🇹🇼"
        case .english:            return "🇺🇸"
        case .turkish:            return "🇹🇷"
        }
    }

    /// 語音辨識 / TTS 用的 Locale
    var locale: Locale { Locale(identifier: bcp47) }

    /// v1.2.5：給 LanguageDetector 用 — NLLanguage rawValue（"zh-Hant"、"en"、"tr"...）對應到 Language case
    init?(forNLCode code: String) {
        switch code {
        case "zh-Hant", "zh-Hans", "zh": self = .traditionalChinese
        case "en":                       self = .english
        case "tr":                       self = .turkish
        default:                         return nil
        }
    }
}

/// 某一對語言對（source → target）。
struct LanguagePair: Hashable, Codable {
    let source: Language
    let target: Language

    /// 支援的方向。Apple Translate iOS 18.4+ 支援 tr↔en、tr↔zh。
    /// 若使用者 iOS 版本不支援，`LanguageAvailability` 會擋下並提示下載。
    static let supported: [LanguagePair] = [
        .init(source: .traditionalChinese, target: .english),
        .init(source: .english,            target: .traditionalChinese),
        .init(source: .turkish,            target: .traditionalChinese),
        .init(source: .traditionalChinese, target: .turkish),
        .init(source: .turkish,            target: .english),
        .init(source: .english,            target: .turkish),
    ]

    var isSupported: Bool { Self.supported.contains(self) }
}
