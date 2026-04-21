import Foundation
import SwiftData

/// v1.1：生詞本 / 字典查詢的資料存取層。
///
/// 設計重點：
///   - 收藏：UI 點星星 → 呼叫 save(...)
///   - 查詢：離線翻譯結果不理想時，DictionaryFallbackService 會查 note
///   - 去重：以 (source, source language, target language) 當唯一鍵
protocol VocabularyRepository {
    func save(_ entry: VocabularyEntry) async throws
    func saveFromResult(_ result: TranslationResult, note: String) async throws
    func exists(sourceText: String, pair: LanguagePair) async throws -> Bool
    func fetchAll() async throws -> [VocabularyEntry]
    func search(keyword: String) async throws -> [VocabularyEntry]
    func delete(id: UUID) async throws
    func clearAll() async throws
}

// MARK: - SwiftData 真實作

@MainActor
final class SwiftDataVocabularyRepository: VocabularyRepository {

    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    func save(_ entry: VocabularyEntry) async throws {
        // 同一組 source / pair 只留一筆，後來的覆蓋前面的 translation + note
        let existing = try await fetch(sourceText: entry.sourceText,
                                        srcCode: entry.sourceLanguageCode,
                                        tgtCode: entry.targetLanguageCode)
        if let old = existing {
            old.translatedText = entry.translatedText
            old.note = entry.note
            old.createdAt = entry.createdAt
        } else {
            context.insert(entry)
        }
        try context.save()
    }

    func saveFromResult(_ result: TranslationResult, note: String) async throws {
        let entry = VocabularyEntry(
            sourceLanguageCode: result.pair.source.bcp47,
            targetLanguageCode: result.pair.target.bcp47,
            sourceText: result.sourceText,
            translatedText: result.translatedText,
            note: note,
            createdAt: result.createdAt
        )
        try await save(entry)
    }

    func exists(sourceText: String, pair: LanguagePair) async throws -> Bool {
        try await fetch(sourceText: sourceText,
                        srcCode: pair.source.bcp47,
                        tgtCode: pair.target.bcp47) != nil
    }

    func fetchAll() async throws -> [VocabularyEntry] {
        let descriptor = FetchDescriptor<VocabularyEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func search(keyword: String) async throws -> [VocabularyEntry] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return try await fetchAll() }
        let descriptor = FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { entry in
                entry.sourceText.localizedStandardContains(trimmed)
                || entry.translatedText.localizedStandardContains(trimmed)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { $0.id == id }
        )
        let matched = try context.fetch(descriptor)
        for entry in matched { context.delete(entry) }
        try context.save()
    }

    func clearAll() async throws {
        let all = try context.fetch(FetchDescriptor<VocabularyEntry>())
        for entry in all { context.delete(entry) }
        try context.save()
    }

    // MARK: Private

    private func fetch(sourceText: String,
                       srcCode: String,
                       tgtCode: String) async throws -> VocabularyEntry? {
        let descriptor = FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { entry in
                entry.sourceText == sourceText
                && entry.sourceLanguageCode == srcCode
                && entry.targetLanguageCode == tgtCode
            }
        )
        return try context.fetch(descriptor).first
    }
}

// MARK: - In-memory 版本（測試 / Preview 用）

final class InMemoryVocabularyRepository: VocabularyRepository {
    private var storage: [VocabularyEntry] = []

    func save(_ entry: VocabularyEntry) async throws {
        if let idx = storage.firstIndex(where: {
            $0.sourceText == entry.sourceText
            && $0.sourceLanguageCode == entry.sourceLanguageCode
            && $0.targetLanguageCode == entry.targetLanguageCode
        }) {
            storage[idx] = entry
        } else {
            storage.insert(entry, at: 0)
        }
    }

    func saveFromResult(_ result: TranslationResult, note: String) async throws {
        let entry = VocabularyEntry(
            sourceLanguageCode: result.pair.source.bcp47,
            targetLanguageCode: result.pair.target.bcp47,
            sourceText: result.sourceText,
            translatedText: result.translatedText,
            note: note,
            createdAt: result.createdAt
        )
        try await save(entry)
    }

    func exists(sourceText: String, pair: LanguagePair) async throws -> Bool {
        storage.contains {
            $0.sourceText == sourceText
            && $0.sourceLanguageCode == pair.source.bcp47
            && $0.targetLanguageCode == pair.target.bcp47
        }
    }

    func fetchAll() async throws -> [VocabularyEntry] { storage }

    func search(keyword: String) async throws -> [VocabularyEntry] {
        let k = keyword.lowercased()
        guard !k.isEmpty else { return storage }
        return storage.filter {
            $0.sourceText.lowercased().contains(k)
            || $0.translatedText.lowercased().contains(k)
        }
    }

    func delete(id: UUID) async throws {
        storage.removeAll { $0.id == id }
    }

    func clearAll() async throws {
        storage.removeAll()
    }
}
