import Foundation

/// 翻譯引擎抽象層。
/// 真實作預設使用 Apple Translation framework；
/// 測試時可以注入 `MTServiceMock`。
protocol MTService {
    /// 翻譯單段文字。
    func translate(text: String, pair: LanguagePair) async throws -> String

    /// 查詢某語言對的語言包狀態。
    func languagePackStatus(for pair: LanguagePair) async throws -> LanguagePackStatus

    /// 觸發下載某語言對的語言包。
    func downloadLanguagePack(for pair: LanguagePair) async throws

    /// 移除某語言對的語言包。
    func removeLanguagePack(for pair: LanguagePair) async throws
}
