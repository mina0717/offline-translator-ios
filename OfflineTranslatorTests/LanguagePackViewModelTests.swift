import XCTest
@testable import OfflineTranslator

// MARK: - ─────────────────────────────────────────────────────────────
// LanguagePackViewModel 單元測試
//
// 覆蓋項目：
//   1. reload()：從 repository 拉語言包清單
//   2. download()：成功時清 error、重拉清單
//   3. download() 被使用者取消：不算錯
//   4. remove()：會拋錯（Apple 不給 API），errorMessage 應被填入 settingsHint
// ─────────────────────────────────────────────────────────────
@MainActor
final class LanguagePackViewModelTests: XCTestCase {

    // MARK: - Mock repository

    final class MockLanguagePackRepository: LanguagePackRepository {
        var listResult: [LanguagePackInfo] = []
        var downloadError: Error?
        var removeError: Error?
        var downloadCalls: [LanguagePair] = []
        var removeCalls: [LanguagePair] = []

        func list() async -> [LanguagePackInfo] { listResult }

        func download(pair: LanguagePair) async throws {
            downloadCalls.append(pair)
            if let e = downloadError { throw e }
        }

        func remove(pair: LanguagePair) async throws {
            removeCalls.append(pair)
            if let e = removeError { throw e }
        }
    }

    // MARK: - reload

    func test_reload_fetchesListFromRepository() async {
        let repo = MockLanguagePackRepository()
        let zhEn = LanguagePair(source: .traditionalChinese, target: .english)
        repo.listResult = [
            LanguagePackInfo(pair: zhEn, status: .ready, estimatedSizeMB: 80)
        ]
        let vm = LanguagePackViewModel(repository: repo)

        await vm.reload()

        XCTAssertEqual(vm.packs.count, 1)
        XCTAssertEqual(vm.packs.first?.pair, zhEn)
        XCTAssertEqual(vm.packs.first?.status, .ready)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - download

    func test_download_success_clearsErrorAndReloads() async {
        let repo = MockLanguagePackRepository()
        let pair = LanguagePair(source: .english, target: .traditionalChinese)
        repo.listResult = [LanguagePackInfo(pair: pair, status: .ready, estimatedSizeMB: 80)]
        let vm = LanguagePackViewModel(repository: repo)
        vm.errorMessage = "old"

        await vm.download(pair)

        XCTAssertEqual(repo.downloadCalls, [pair])
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.downloadingPair)
        XCTAssertEqual(vm.packs.count, 1)
    }

    func test_download_cancellationError_isSilentlyIgnored() async {
        let repo = MockLanguagePackRepository()
        repo.downloadError = CancellationError()
        let vm = LanguagePackViewModel(repository: repo)

        await vm.download(.init(source: .english, target: .traditionalChinese))

        XCTAssertNil(vm.errorMessage, "使用者按『取消』不應被當作錯誤")
    }

    func test_download_realError_setsErrorMessage() async {
        let repo = MockLanguagePackRepository()
        repo.downloadError = TranslationError.modelNotAvailable
        let vm = LanguagePackViewModel(repository: repo)

        await vm.download(.init(source: .english, target: .traditionalChinese))

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - remove

    func test_remove_whenRepositoryThrows_setsSettingsHint() async {
        struct RemoveNotSupported: LocalizedError {
            var errorDescription: String? { "請到設定 → 一般 → 語言與地區 → 翻譯" }
        }
        let repo = MockLanguagePackRepository()
        repo.removeError = RemoveNotSupported()
        let vm = LanguagePackViewModel(repository: repo)

        await vm.remove(.init(source: .english, target: .traditionalChinese))

        XCTAssertNotNil(vm.settingsHint,
                       "Apple 不允許程式刪語言包，應顯示引導到設定的提示")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Dismiss helpers

    func test_dismissErrors_clearsFlags() {
        let repo = MockLanguagePackRepository()
        let vm = LanguagePackViewModel(repository: repo)
        vm.errorMessage = "x"
        vm.settingsHint = "y"

        vm.dismissError()
        vm.dismissSettingsHint()

        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.settingsHint)
    }
}
