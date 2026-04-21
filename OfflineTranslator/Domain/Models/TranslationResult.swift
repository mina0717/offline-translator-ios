import Foundation

/// 一次翻譯的「輸入」
struct TranslationRequest: Hashable {
    let text: String
    let pair: LanguagePair
}

/// 一次翻譯的「輸出」
struct TranslationResult: Hashable {
    let sourceText: String
    let translatedText: String
    let pair: LanguagePair
    /// 產生時間（之後寫入歷史紀錄用）
    let createdAt: Date
}

/// 翻譯流程常見錯誤。ViewModel / UseCase 透過這個統一對外報錯。
enum TranslationError: LocalizedError {
    /// 空字串或僅有空白
    case emptyInput
    /// 使用的語言對不在 MVP 支援清單
    case unsupportedPair
    /// Apple Translation 尚未下載對應語言包
    case modelNotAvailable
    /// Apple Translation 或其他底層 SDK 的錯誤
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .emptyInput:        return "請先輸入要翻譯的文字。"
        case .unsupportedPair:   return "目前不支援這個翻譯方向。"
        case .modelNotAvailable: return "尚未下載對應的語言包，請先到「語言包管理」下載。"
        case .underlying(let e): return e.localizedDescription
        }
    }
}
