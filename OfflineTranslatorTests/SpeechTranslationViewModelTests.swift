import XCTest
@testable import OfflineTranslator

// MARK: - ──────────────────────────────────────────────────────────────
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

    // MARK: - retryTranslation() (v1.1 新增)
    //
    // 情境：第一次翻譯失敗 → 使用者點「重試翻譯」。
    // 期望：用既有的 finalTranscript 再翻一次，不需要重錄。
    // 覆蓋：
    //   1. 一開始 MT 丟錯 → errorMessage 被填、phase 回 idle
    //   2. 把 mt.nextError 清空後呼叫 retryTranslation()
    //      → 重用 finalTranscript、translatedText 正常、phase 回 .done、errorMessage 被清掉
    //   3. finalTranscript 是空的時候 retryTranslation() 應該直接 no-op

    func test_retryTranslation_reusesFinalTranscript_afterMTError() async {
        let (vm, _, mt, _) = makeVM(cannedFinal: "早安")
        mt.nextError = .modelNotAvailable       // 第一次會翻譯失敗
        vm.sourceLanguage = .traditionalChinese
        vm.targetLanguage = .english

        vm.startHold()
        try? await Task.sleep(nanoseconds: 200_000_000)
        await vm.releaseHold()

        // 確認第一次真的失敗了
        XCTAssertEqual(vm.phase, .idle, "MT 失敗後應回到 idle")
        XCTAssertNotNil(vm.errorMessage, "MT 失敗後應有錯誤訊息")
        XCTAssertEqual(vm.finalTranscript, "早安", "finalTranscript 應保留給重試用")
        XCTAssertTrue(vm.translatedText.isEmpty)

        // 修好錯誤 → 點重試
        mt.nextError = nil
        await vm.retryTranslation()

        XCTAssertEqual(vm.phase, .done, "重試成功後應進入 .done")
        XCTAssertNil(vm.errorMessage, "重試成功後 errorMessage 應被清掉")
        XCTAssertFalse(vm.translatedText.isEmpty, "應該產生譯文")
        XCTAssertTrue(vm.translatedText.contains("zh-Hant→en"),
                      "MTServiceMock 的格式包含 zh-Hant→en，用來驗證走到了翻譯")
    }

    func test_retryTranslation_emptyTranscript_noop() async {
        let (vm, _, _, _) = makeVM()
        vm.finalTranscript = ""        // 空的
        vm.phase = .idle
        vm.errorMessage = "舊錯誤"

        await vm.retryTranslation()

        // no-op：什麼都沒改、phase 保持原樣、errorMessage 不會被清
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.translatedText.isEmpty)
        XCTAssertEqual(vm.errorMessage, "舊錯誤",
                       "finalTranscript 是空的時候不應該清掉既有錯誤訊息")
    }

    func test_retryTranslation_ignoredWhileTranslating() async {
        let (vm, _, _, _) = makeVM()
        vm.finalTranscript = "早安"
        vm.phase = .translating        // 已經在翻譯中了

        await vm.retryTranslation()    // 應該 no-op

        // phase 不會被改、也不會產生新的 translatedText
        XCTAssertEqual(vm.phase, .translating)
    }
}
