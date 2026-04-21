import Foundation
import SwiftData

/// v1.1：收藏的單字 / 短句。
/// 使用者在翻譯結果旁點星星就會存進這裡。
@Model
final class VocabularyEntry {
    /// 主鍵
    var id: UUID
    /// 來源語言 BCP-47
    var sourceLanguageCode: String
    /// 目標語言 BCP-47
    var targetLanguageCode: String
    /// 原文（通常是單字或短句）
    var sourceText: String
    /// 譯文
    var translatedText: String
    /// 可選備註（使用者自己補充的例句、發音提示等）
    var note: String
    /// 加入時間
    var createdAt: Date

    init(
        id: UUID = .init(),
        sourceLanguageCode: String,
        targetLanguageCode: String,
        sourceText: String,
        translatedText: String,
        note: String = "",
        createdAt: Date = .init()
    ) {
        self.id = id
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.note = note
        self.createdAt = createdAt
    }
}
