import Foundation

/// v1.1：離線字典 fallback。
///
/// 為什麼需要：
///   Apple Translation 是整句翻譯模型，碰到單字（「apple」「禮貌」）或
///   成語、俚語時偶爾會給很怪的結果。這個 service 提供一個輕量的
///   「對照詞庫」，翻譯流程可以先查這裡，查不到再走 MT。
///
/// 實作：
///   - 詞庫用內建 JSON（小量、不佔 bundle 空間）
///   - 未來可擴充為 Core ML 詞向量 / 小語言模型
///   - 完全離線，無網路呼叫
///
/// 使用流程：
///   if let entry = DictionaryFallbackService.shared.lookup(...) { 用 entry.definition }
///   else { 走 MT 翻譯 }
protocol DictionaryLookupService {
    func lookup(word: String, pair: LanguagePair) -> DictionaryEntry?
}

struct DictionaryEntry: Hashable {
    let source: String
    let translations: [String]   // 可能有多個解釋
    let partOfSpeech: String?    // 名詞/動詞/形容詞 — 可為空
    let example: String?         // 例句 — 可為空

    /// 給 UI 用的單行呈現
    var primaryTranslation: String {
        translations.first ?? ""
    }

    /// 給 VocabularyEntry.note 用的完整摘要
    var noteSummary: String {
        var parts: [String] = []
        if let pos = partOfSpeech, !pos.isEmpty { parts.append("(\(pos))") }
        if translations.count > 1 {
            parts.append(translations.joined(separator: " / "))
        }
        if let example, !example.isEmpty { parts.append("例句：\(example)") }
        return parts.joined(separator: " ")
    }
}

final class DictionaryFallbackService: DictionaryLookupService {

    static let shared = DictionaryFallbackService()

    /// 內建迷你詞庫（v1.1 以展示為主，未來從 bundled JSON 讀）
    /// Key 格式：`"\(word)|\(srcCode)|\(tgtCode)"` 小寫
    private let dictionary: [String: DictionaryEntry]

    init(entries: [DictionaryEntry] = Self.defaultEntries) {
        var dict: [String: DictionaryEntry] = [:]
        for entry in entries {
            // 建立 zh↔en 兩個方向的索引
            dict[Self.key(entry.source, "en", "zh-Hant")] = entry
            if let first = entry.translations.first {
                dict[Self.key(first, "zh-Hant", "en")] = DictionaryEntry(
                    source: first,
                    translations: [entry.source],
                    partOfSpeech: entry.partOfSpeech,
                    example: entry.example
                )
            }
        }
        self.dictionary = dict
    }

    func lookup(word: String, pair: LanguagePair) -> DictionaryEntry? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 只對單字（不含空白）查 fallback；完整句子還是交給 MT
        guard !trimmed.contains(" ") && trimmed.count <= 30 else { return nil }
        let k = Self.key(trimmed, pair.source.bcp47, pair.target.bcp47)
        return dictionary[k]
    }

    private static func key(_ word: String, _ src: String, _ tgt: String) -> String {
        "\(word.lowercased())|\(src)|\(tgt)"
    }
}

// MARK: - 預設詞庫（演示用；v1.1 後從 bundled JSON 載入）

extension DictionaryFallbackService {
    /// 小型示範詞庫：挑 Apple Translation 曾經翻錯的案例
    static let defaultEntries: [DictionaryEntry] = [
        DictionaryEntry(
            source: "apple",
            translations: ["蘋果", "蘋果公司"],
            partOfSpeech: "n.",
            example: "I eat an apple a day."
        ),
        DictionaryEntry(
            source: "bank",
            translations: ["銀行", "河岸", "堤岸"],
            partOfSpeech: "n.",
            example: "I went to the bank to deposit a check."
        ),
        DictionaryEntry(
            source: "break",
            translations: ["打破", "休息", "中斷"],
            partOfSpeech: "v./n.",
            example: "Let's take a break."
        ),
        DictionaryEntry(
            source: "run",
            translations: ["跑", "運行", "經營"],
            partOfSpeech: "v.",
            example: "She runs a small business."
        ),
        DictionaryEntry(
            source: "book",
            translations: ["書", "預訂"],
            partOfSpeech: "n./v.",
            example: "I want to book a flight."
        ),
        DictionaryEntry(
            source: "light",
            translations: ["光", "燈", "輕的"],
            partOfSpeech: "n./adj.",
            example: "Turn on the light."
        ),
        DictionaryEntry(
            source: "cool",
            translations: ["涼爽的", "酷的", "冷靜"],
            partOfSpeech: "adj.",
            example: "That's really cool!"
        ),
        DictionaryEntry(
            source: "fair",
            translations: ["公平的", "金髮的", "市集"],
            partOfSpeech: "adj./n.",
            example: "That's not fair."
        ),
        DictionaryEntry(
            source: "match",
            translations: ["比賽", "火柴", "搭配"],
            partOfSpeech: "n./v.",
            example: "The colors match perfectly."
        ),
        DictionaryEntry(
            source: "spring",
            translations: ["春天", "彈簧", "泉水"],
            partOfSpeech: "n.",
            example: "Spring is my favorite season."
        )
    ]
}
