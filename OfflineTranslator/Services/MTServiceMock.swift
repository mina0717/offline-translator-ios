import Foundation

/// 開發 / 測試用的假翻譯引擎。
/// 在輸入文字前後加上 `[zh→en]`、`[en→zh]` 等標記，方便人眼確認流程通了。
final class MTServiceMock: MTService {
    /// 模擬延遲（秒）；測試時可以改 0。
    var simulatedLatency: Double = 0.4
    /// 控制 `translate` 是否要 throw 一個指定錯誤（單元測試用）。
    var nextError: TranslationError?

    func translate(text: String, pair: LanguagePair) async throws -> String {
        if let error = nextError { throw error }
        if simulatedLatency > 0 {
            try? await Task.sleep(nanoseconds: UInt64(simulatedLatency * 1_000_000_000))
        }
        let tag = "[\(pair.source.bcp47)→\(pair.target.bcp47)]"
        return "\(tag) \(text)"
    }

    func languagePackStatus(for pair: LanguagePair) async throws -> LanguagePackStatus {
        // Mock 預設：所有語言對都已下載。
        .ready
    }

    func downloadLanguagePack(for pair: LanguagePair) async throws { /* no-op */ }
    func removeLanguagePack(for pair: LanguagePair) async throws   { /* no-op */ }
}
