import Foundation

/// App 目前支援的語言清單。
/// **MVP 縮減範圍（2026-04-20）：只做繁中 (zh-Hant) 與英文 (en)**
/// 之後要加語言只需要在這裡加 case 並補 `displayName` / `bcp47`。
///
/// 歷史：曾規劃支援日文 (ja)，因 13 天時程壓力縮減範圍，
/// 日文 / 韓文延至 v1.1。日文對應 bcp47 為 `"ja"`，若未來恢復，
/// 同步更新 `LanguagePair.supported`、`LanguageDetector` 與 UI 文案。
enum Language: String, CaseIterable, Identifiable, Codable, Hashable {
    case traditionalChinese
    case english

    var id: String { rawValue }

    /// BCP-47 語系代碼。Apple Translation / Speech / Vision 都用這個。
    var bcp47: String {
        switch self {
        case .traditionalChinese: return "zh-Hant"
        case .english:            return "en"
        }
    }

    /// UI 顯示名稱（繁中）
    var displayName: String {
        switch self {
        case .traditionalChinese: return "繁體中文"
        case .english:            return "English"
        }
    }

    /// UI 上顯示的國旗 emoji（視覺輔助）
    var flag: String {
        switch self {
        case .traditionalChinese: return "🇹🇼"
        case .english:            return "🇺🇸"
        }
    }

    /// 語音辨識 / TTS 用的 Locale
    var locale: Locale { Locale(identifier: bcp47) }
}

/// 某一對語言對（source → target）。
/// **MVP 縮減範圍：只支援繁中 ⇄ 英文兩個方向。**
struct LanguagePair: Hashable, Codable {
    let source: Language
    let target: Language

    /// MVP 支援的兩個方向。其他方向（例如同語言互譯、未來新增語言）拒絕，
    /// 避免 Apple Translation 在未支援語言對上跳出未預期 UI。
    static let supported: [LanguagePair] = [
        .init(source: .traditionalChinese, target: .english),
        .init(source: .english,            target: .traditionalChinese),
    ]

    var isSupported: Bool { Self.supported.contains(self) }
}
