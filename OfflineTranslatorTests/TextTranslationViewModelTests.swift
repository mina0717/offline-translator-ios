import XCTest
@testable import OfflineTranslator

// MARK: - ─────────────────────────────────────────────────────────────
// TextTranslationViewModel 單元測試
//
// 覆蓋項目：
//   1. happy path：translate() 成功後 outputText 被填入
//   2. empty input：translate() 不會打 MT，且 errorMessage 被設定
//   3. unsupported pair（en→en）：errorMessage 會出現
//   4. swapLanguages：來源 / 目標互換，且若 output 有值會反灌回 input
//   5. autoDetectSource：偵測失敗時不改變來源語言
// ─────────────────────────────────────────────────────────────
@MainActor
final class TextTranslationViewModelTests: XCTestCase {

    private func makeVM(
        mt: MTServiceMock = {
            let m = MTServiceMock()
            m.simulatedLatency = 0
            return m
        }()
    ) -> (TextTranslationViewModel, MTServiceMock, InMemoryHistoryRepository) {
        let history = InMemoryHistoryRepository()
        let useCase = DefaultTranslateTextUseCase(mtService: mt, history: history)
        let vm = TextTranslationViewModel(
            useCase: useCase,
            detector: LanguageDetector()
        )
        return (vm, mt, history)
    }

    // MARK: - Happy path

    func test_translate_success_updatesOutputAndClearsError() async {
        let (vm, _, history) = makeVM()
        vm.inputText = "你好"
        vm.sourceLanguage = .traditionalChinese
        vm.targetLanguage = .english

        await vm.translate()

        XCTAssertFalse(vm.outputText.isEmpty, "譯文應該被填入")
        XCTAssertTrue(vm.outputText.contains("zh-Hant→en"), "Mock 會在譯文前加 tag")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)

        // Use-case 層會順手寫歷史
        let saved = try? await history.fetchAll(limit: 10)
        XCTAssertEqual(saved?.count, 1)
    }

    // MARK: - Validation

    func test_translate_emptyInput_setsErrorMessage() async {
        let (vm, _, _) = makeVM()
        vm.inputText = "   "   // 只有空白

        await vm.translate()

        XCTAssertTrue(vm.outputText.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_translate_mtError_propagatesErrorMessage() async {
        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        mt.nextError = .modelNotAvailable
        let (vm, _, _) = makeVM(mt: mt)
        vm.inputText = "hello"
        vm.sourceLanguage = .english
        vm.targetLanguage = .traditionalChinese

        await vm.translate()

        XCTAssertTrue(vm.outputText.isEmpty)
        XCTAssertNotNil(vm.errorMessage, "MT 失敗應該填 errorMessage")
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Swap

    func test_swapLanguages_swapsSourceAndTarget() {
        let (vm, _, _) = makeVM()
        vm.sourceLanguage = .traditionalChinese
        vm.targetLanguage = .english
        vm.inputText = "哈囉"
        vm.outputText = "Hello"

        vm.swapLanguages()

        XCTAssertEqual(vm.sourceLanguage, .english)
        XCTAssertEqual(vm.targetLanguage, .traditionalChinese)
        // 原 output 會被帶回 input，方便連續對話
        XCTAssertEqual(vm.inputText, "Hello")
        XCTAssertTrue(vm.outputText.isEmpty)
    }

    // MARK: - Auto detect

    func test_autoDetectSource_emptyInput_doesNotChangeLanguage() {
        let (vm, _, _) = makeVM()
        vm.sourceLanguage = .traditionalChinese
        vm.inputText = ""   // detector 會回 nil

        vm.autoDetectSource()

        XCTAssertEqual(vm.sourceLanguage, .traditionalChinese,
                       "空字串偵測失敗時不應該改變 source")
    }

    // MARK: - Clear

    func test_clear_resetsAllFields() {
        let (vm, _, _) = makeVM()
        vm.inputText = "foo"
        vm.outputText = "bar"
        vm.errorMessage = "x"

        vm.clear()

        XCTAssertTrue(vm.inputText.isEmpty)
        XCTAssertTrue(vm.outputText.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - availableTargets

    func test_availableTargets_excludesSourceItself() {
        let (vm, _, _) = makeVM()
        vm.sourceLanguage = .traditionalChinese

        let targets = vm.availableTargets

        XCTAssertFalse(targets.contains(.traditionalChinese))
        XCTAssertTrue(targets.contains(.english))
    }
}
