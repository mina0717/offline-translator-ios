import XCTest
@testable import OfflineTranslator

// MARK: - ─────────────────────────────────────────────────────────────
// SpeechTranslationViewModel 單元測試
//
// 覆蓋項目：
//   1. happy path：startHold → releaseHold → translatedText 非空、phase 變 .done
//   2. swapLanguages：來源 / 目標互換，且清空上一輪結果
//   3. clear()：回到 idle 狀態
//   4. releaseHold 空 transcript：不會翻譯，phase 直接回 idle
//
// 備註：
//   - 這裡用 ASRServiceMock 會逐字 yield 並 finish()，我們 await 一小段時間
//     讓 Task 跑完；實際 production code 不需要 sleep。
// ─────────────────────────────────────────────────────────────
@MainActor
final class SpeechTranslationViewModelTests: XCTestCase {

    private func makeVM(
        cannedFinal: String = "你好世界",
        mtError: TranslationError? = nil
    ) -> (SpeechTranslationViewModel, ASRServiceMock, MTServiceMock, TTSServiceMock) {
        let asr = ASRServiceMock()
        asr.cannedFinalText = cannedFinal

        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        mt.nextError = mtError

        let tts = TTSServiceMock()
        let history = InMemoryHistoryRepository()

        let useCase = DefaultSpeechTranslateUseCase(
            asrService: asr,
            mtService: mt,
            ttsService: tts,
            history: history
        )
        let vm = SpeechTranslationViewModel(useCase: useCase)
        return (vm, asr, mt, tts)
    }

    // MARK: - Happy path

    func test_startHold_thenRelease_completesWithTranslation() async {
        let (vm, _, _, tts) = makeVM(cannedFinal: "你好")
        vm.sourceLanguage = .traditionalChinese
        vm.targetLanguage = .english

        vm.startHold()
        XCTAssertEqual(vm.phase, .recording)

        // 給 mock 一點時間 yield partial（80ms × 2 字 ≈ 160ms）
        try? await Task.sleep(nanoseconds: 300_000_000)

        await vm.releaseHold()

        XCTAssertEqual(vm.phase, .done)
        XCTAssertEqual(vm.finalTranscript, "你好")
        XCTAssertFalse(vm.translatedText.isEmpty)
        XCTAssertTrue(vm.translatedText.contains("zh-Hant→en"))
        XCTAssertEqual(tts.lastSpokenText, vm.translatedText,
                       "完成翻譯後應自動朗讀譯文")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Empty transcript

    func test_releaseHold_emptyTranscript_goesBackToIdle() async {
        let (vm, _, _, _) = makeVM(cannedFinal: "")

        vm.startHold()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await vm.releaseHold()

        XCTAssertEqual(vm.phase, .idle, "空辨識應該直接回 idle，不進翻譯")
        XCTAssertTrue(vm.translatedText.isEmpty)
    }

    // MARK: - Swap

    func test_swapLanguages_swapsAndClearsPreviousResult() {
        let (vm, _, _, _) = makeVM()
        vm.sourceLanguage = .traditionalChinese
        vm.targetLanguage = .english
        vm.finalTranscript = "你好"
        vm.translatedText = "Hello"

        vm.swapLanguages()

        XCTAssertEqual(vm.sourceLanguage, .english)
        XCTAssertEqual(vm.targetLanguage, .traditionalChinese)
        XCTAssertTrue(vm.finalTranscript.isEmpty)
        XCTAssertTrue(vm.translatedText.isEmpty)
    }

    func test_swapLanguages_ignoredWhileRecording() {
        let (vm, _, _, _) = makeVM()
        vm.sourceLanguage = .traditionalChinese
        vm.targetLanguage = .english
        vm.phase = .recording

        vm.swapLanguages()   // 應該 no-op

        XCTAssertEqual(vm.sourceLanguage, .traditionalChinese)
        XCTAssertEqual(vm.targetLanguage, .english)
    }

    // MARK: - Clear

    func test_clear_resetsToIdle() {
        let (vm, _, _, _) = makeVM()
        vm.partialTranscript = "x"
        vm.finalTranscript = "y"
        vm.translatedText = "z"
        vm.errorMessage = "err"
        vm.phase = .done

        vm.clear()

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.partialTranscript.isEmpty)
        XCTAssertTrue(vm.finalTranscript.isEmpty)
        XCTAssertTrue(vm.translatedText.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }
}
