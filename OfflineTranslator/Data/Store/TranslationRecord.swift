import Foundation
import SwiftData

/// SwiftData 的歷史紀錄 model。
/// 一筆 = 一次翻譯結果，含時間戳記、語言對與內文。
@Model
final class TranslationRecord {
    /// 主鍵（UUID）
    var id: UUID
    /// 來源語言 BCP-47（MVP：zh-Hant / en）
    var sourceLanguageCode: String
    /// 目標語言 BCP-47
    var targetLanguageCode: String
    /// 原文
    var sourceText: String
    /// 譯文
    var translatedText: String
    /// 建立時間
    var createdAt: Date

    init(
        id: UUID = .init(),
        sourceLanguageCode: String,
        targetLanguageCode: String,
        sourceText: String,
        translatedText: String,
        createdAt: Date
    ) {
        self.id = id
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.createdAt = createdAt
    }
}

extension TranslationRecord {
    /// 把 SwiftData record 轉回 Domain 物件（給 UI / UseCase 用）。
    func toResult() -> TranslationResult? {
        guard
            let source = Language.allCases.first(where: { $0.bcp47 == sourceLanguageCode }),
            let target = Language.allCases.first(where: { $0.bcp47 == targetLanguageCode })
        else { return nil }

        return TranslationResult(
            sourceText: sourceText,
            translatedText: translatedText,
            pair: .init(source: source, target: target),
            createdAt: createdAt
        )
    }
}
