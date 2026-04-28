import Foundation
import SwiftData

/// 歷史紀錄資料存取介面。
/// UseCase / ViewModel 只依賴這個 protocol，方便 mock。
protocol HistoryRepository {
    func save(_ result: TranslationResult) async throws
    func fetchAll(limit: Int?) async throws -> [TranslationResult]
    func delete(id: UUID) async throws
    func clearAll() async throws
}

/// SwiftData 的真實作。
/// 注意：這裡用 @MainActor 是因為 ModelContext 預設要在 main actor 上操作。
/// 真實作之後可以拆 Background context（如果寫入頻率變高）。
@MainActor
final class SwiftDataHistoryRepository: HistoryRepository {

    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    func save(_ result: TranslationResult) async throws {
        let record = TranslationRecord(
            sourceLanguageCode: result.pair.source.bcp47,
            targetLanguageCode: result.pair.target.bcp47,
            sourceText: result.sourceText,
            translatedText: result.translatedText,
            createdAt: result.createdAt
        )
        context.insert(record)
        try context.save()
    }

    func fetchAll(limit: Int?) async throws -> [TranslationResult] {
        var descriptor = FetchDescriptor<TranslationRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // v1.2.2：預設只抓最近 200 筆，避免歷史多時 History 頁卡住
        descriptor.fetchLimit = limit ?? 200
        let records = try context.fetch(descriptor)
        return records.compactMap { $0.toResult() }
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<TranslationRecord>(
            predicate: #Predicate { $0.id == id }
        )
        let matched = try context.fetch(descriptor)
        for record in matched {
            context.delete(record)
        }
        try context.save()
    }

    func clearAll() async throws {
        let all = try context.fetch(FetchDescriptor<TranslationRecord>())
        for r in all { context.delete(r) }
        try context.save()
    }
}

/// 測試用 in-memory 版本（不依賴 SwiftData）。
final class InMemoryHistoryRepository: HistoryRepository {
    private var storage: [TranslationResult] = []

    func save(_ result: TranslationResult) async throws {
        storage.insert(result, at: 0)
    }

    func fetchAll(limit: Int?) async throws -> [TranslationResult] {
        if let limit { return Array(storage.prefix(limit)) }
        return storage
    }

    func delete(id: UUID) async throws { /* InMemory 簡化版不支援 by id */ }
    func clearAll() async throws { storage.removeAll() }
}
