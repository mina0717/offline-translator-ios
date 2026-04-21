import XCTest
@testable import OfflineTranslator

// MARK: - ─────────────────────────────────────────────────────────────
// HistoryViewModel 單元測試
//
// 覆蓋項目：
//   1. reload()：從 repository 拉最多 100 筆
//   2. clearAll()：清空後 records 應該是空陣列
//   3. repository 失敗時 records 會被設為空陣列（不崩潰）
// ─────────────────────────────────────────────────────────────
@MainActor
final class HistoryViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSampleResult(text: String = "hi") -> TranslationResult {
        TranslationResult(
            sourceText: text,
            translatedText: "[zh-Hant→en] \(text)",
            pair: .init(source: .traditionalChinese, target: .english),
            createdAt: Date()
        )
    }

    // MARK: - reload

    func test_reload_fetchesFromRepository() async {
        let repo = InMemoryHistoryRepository()
        try? await repo.save(makeSampleResult(text: "A"))
        try? await repo.save(makeSampleResult(text: "B"))
        let vm = HistoryViewModel(repository: repo)

        await vm.reload()

        XCTAssertEqual(vm.records.count, 2)
    }

    // MARK: - clearAll

    func test_clearAll_emptiesRecords() async {
        let repo = InMemoryHistoryRepository()
        try? await repo.save(makeSampleResult())
        let vm = HistoryViewModel(repository: repo)
        await vm.reload()
        XCTAssertEqual(vm.records.count, 1)

        await vm.clearAll()

        XCTAssertTrue(vm.records.isEmpty)
    }

    // MARK: - Failure handling

    func test_reload_whenRepositoryThrows_setsEmptyArray() async {
        final class ThrowingRepo: HistoryRepository {
            func save(_ result: TranslationResult) async throws {}
            func fetchAll(limit: Int?) async throws -> [TranslationResult] {
                throw NSError(domain: "test", code: -1)
            }
            func delete(id: UUID) async throws {}
            func clearAll() async throws {}
        }
        let vm = HistoryViewModel(repository: ThrowingRepo())

        await vm.reload()

        XCTAssertTrue(vm.records.isEmpty, "repo 失敗時不應崩潰")
    }
}
