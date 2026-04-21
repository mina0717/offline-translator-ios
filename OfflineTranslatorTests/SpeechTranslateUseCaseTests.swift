import XCTest
@testable import OfflineTranslator

/// UseCase 邊界測試：DefaultSpeechTranslateUseCase
/// 重點：
///   1. startRecognition / stopRecognition 直接透傳 ASRService
///   2. translate 要 trim、擋空白、擋 unsupported pair、寫 history
///   3. speak 透傳到 TTSService
///   4. history.save 失敗不能弄掛 translate
final class SpeechTranslateUseCaseTests: XCTestCase {

    // MARK: - ASR passthrough

    func test_startRecognition_streamsPartialsFromASRService() async throws {
        let asr = ASRServiceMock()
        asr.cannedFinalText = "abc"
        let useCase = DefaultSpeechTranslateUseCase(
            asrService: asr,
            mtService: MTServiceMock(),
            ttsService: TTSServiceMock(),
            history: InMemoryHistoryRepository()
        )

        var received: [String] = []
        for try await partial in useCase.startRecognition(in: .english) {
            received.append(partial)
        }
        // ASRServiceMock 會逐字 yield：a, ab, abc
        XCTAssertEqual(received, ["a", "ab", "abc"])
    }

    func test_stopRecognition_returnsFinalTextFromASRService() async throws {
        let asr = ASRServiceMock()
        asr.cannedFinalText = "Hello World"
        let useCase = DefaultSpeechTranslateUseCase(
            asrService: asr,
            mtService: MTServiceMock(),
            ttsService: TTSServiceMock(),
            history: InMemoryHistoryRepository()
        )

        let finalText = try await useCase.stopRecognition()
        XCTAssertEqual(finalText, "Hello World")
    }

    // MARK: - translate

    func test_translate_happyPath_savesHistory() async throws {
        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        let history = InMemoryHistoryRepository()
        let useCase = DefaultSpeechTranslateUseCase(
            asrService: ASRServiceMock(),
            mtService: mt,
            ttsService: TTSServiceMock(),
            history: history
        )

        let result = try await useCase.translate(
            "  hello  ",
            pair: .init(source: .english, target: .traditionalChinese)
        )
        // UseCase 應該要 trim
        XCTAssertEqual(result.sourceText, "hello")
        XCTAssertTrue(result.translatedText.contains("en→zh-Hant"))

        let saved = try await history.fetchAll(limit: nil)
        XCTAssertEqual(saved.count, 1)
    }

    func test_translate_emptyInput_throws() async {
        let useCase = DefaultSpeechTranslateUseCase(
            asrService: ASRServiceMock(),
            mtService: MTServiceMock(),
            ttsService: TTSServiceMock(),
            history: InMemoryHistoryRepository()
        )
        do {
            _ = try await useCase.translate(
                "   \n  ",
                pair: .init(source: .english, target: .traditionalChinese)
            )
            XCTFail("Expected emptyInput")
        } catch let error as TranslationError {
            if case .emptyInput = error { /* ok */ } else {
                XCTFail("Wrong TranslationError: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_translate_unsupportedPair_throws() async {
        let useCase = DefaultSpeechTranslateUseCase(
            asrService: ASRServiceMock(),
            mtService: MTServiceMock(),
            ttsService: TTSServiceMock(),
            history: InMemoryHistoryRepository()
        )
        do {
            _ = try await useCase.translate(
                "hello",
                pair: .init(source: .english, target: .english)
            )
            XCTFail("Expected unsupportedPair")
        } catch let error as TranslationError {
            if case .unsupportedPair = error { /* ok */ } else {
                XCTFail("Wrong TranslationError: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_translate_mtError_propagates() async {
        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        mt.nextError = .modelNotAvailable
        let useCase = DefaultSpeechTranslateUseCase(
            asrService: ASRServiceMock(),
            mtService: mt,
            ttsService: TTSServiceMock(),
            history: InMemoryHistoryRepository()
        )
        do {
            _ = try await useCase.translate(
                "hello",
                pair: .init(source: .english, target: .traditionalChinese)
            )
            XCTFail("Expected modelNotAvailable")
        } catch let error as TranslationError {
            if case .modelNotAvailable = error { /* ok */ } else {
                XCTFail("Wrong TranslationError: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - speak

    func test_speak_passesThroughTTSService() async throws {
        let tts = TTSServiceMock()
        let useCase = DefaultSpeechTranslateUseCase(
            asrService: ASRServiceMock(),
            mtService: MTServiceMock(),
            ttsService: tts,
            history: InMemoryHistoryRepository()
        )
        try await useCase.speak("Hi there", language: .english)
        XCTAssertEqual(tts.lastSpokenText, "Hi there")
    }
}
