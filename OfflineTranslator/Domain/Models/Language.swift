import Foundation

/// App 目前支援的語言清單。
///
/// v1.3.0 (v13.6 擴充)：新增西班牙／泰／越南／葡萄牙／義大利／印尼／荷蘭 7 種，
/// 加上 v1.3.0 主版的日韓德法 4 種，**共 14 種語言、14×13 = 182 個翻譯方向**。
/// v1.3.0：新增日／韓／德／法 4 個語言。
/// v1.2.5：加入土耳其文（Apple Translate iOS 18.4+ 支援）。
///
/// **未支援**：克羅埃西亞文、希伯來文、波斯文等（Apple Translate 框架未涵蓋）。
///
/// **SwiftData 相容性**：raw value 沿用 case name 字串，新增 case 不影響舊資料解碼。
enum Language: String, CaseIterable, Identifiable, Codable, Hashable {
    case traditionalChinese
    case english
    case turkish
    // v1.3.0 第一波
    case japanese
    case korean
    case german
    case french
    // v1.3.0 / v13.6 第二波（同 v1.3.0 上架前一起加）
    case spanish
    case thai
    case vietnamese
    case portuguese
    case italian
    case indonesian
    case dutch

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
        // v13.6 新增
        case .spanish:            return "es-ES"
        case .thai:               return "th-TH"
        case .vietnamese:         return "vi-VN"
        case .portuguese:         return "pt-BR"   // Apple framework 用巴西葡萄牙文
        case .italian:            return "it-IT"
        case .indonesian:         return "id-ID"
        case .dutch:              return "nl-NL"
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
        case .spanish:            return "Español"
        case .thai:               return "ไทย"
        case .vietnamese:         return "Tiếng Việt"
        case .portuguese:         return "Português"
        case .italian:            return "Italiano"
        case .indonesian:         return "Bahasa Indonesia"
        case .dutch:              return "Nederlands"
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
        case .spanish:            return "🇪🇸"
        case .thai:               return "🇹🇭"
        case .vietnamese:         return "🇻🇳"
        case .portuguese:         return "🇵🇹"   // 旗幟用葡萄牙（雖然語料是巴西葡），符合多數使用者預期
        case .italian:            return "🇮🇹"
        case .indonesian:         return "🇮🇩"
        case .dutch:              return "🇳🇱"
        }
    }

    /// 語音辨識 / TTS 用的 Locale
    var locale: Locale { Locale(identifier: bcp47) }

    /// 給 LanguageDetector 用 — NLLanguage rawValue 對應到 Language case
    init?(forNLCode code: String) {
        switch code {
        case "zh-Hant", "zh-Hans", "zh": self = .traditionalChinese
        case "en":                       self = .english
        case "tr":                       self = .turkish
        case "ja":                       self = .japanese
        case "ko":                       self = .korean
        case "de":                       self = .german
        case "fr":                       self = .french
        // v13.6
        case "es":                       self = .spanish
        case "th":                       self = .thai
        case "vi":                       self = .vietnamese
        case "pt":                       self = .portuguese
        case "it":                       self = .italian
        case "id":                       self = .indonesian
        case "nl":                       self = .dutch
        default:                         return nil
        }
    }
}

/// 某一對語言對（source → target）。
struct LanguagePair: Hashable, Codable {
    let source: Language
    let target: Language

    /// v1.3.0：動態生成所有 N×(N-1) 個有效配對（排除自我翻譯）。
    /// v13.6：14 種語言 → 14×13 = **182 個配對**。
    ///
    /// Apple Translation Framework 在 runtime 會用 `LanguageAvailability.status(from:to:)`
    /// 確認個別配對在當前 iOS 版本是否可用；不可用 case 會跳系統提示。
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
