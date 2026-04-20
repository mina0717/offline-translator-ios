import XCTest
@testable import OfflineTranslator

final class TranslateTextUseCaseTests: XCTestCase {

    // MARK: - Happy path

    func test_execute_returnsTranslatedResult_andSavesHistory() async throws {
        // Given
        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        let history = InMemoryHistoryRepository()
        let useCase = DefaultTranslateTextUseCase(mtService: mt, history: history)

        let request = TranslationRequest(
            text: "你好世界",
            pair: .init(source: .traditionalChinese, target: .english)
        )

        // When
        let result = try await useCase.execute(request)

        // Then
        XCTAssertEqual(result.sourceText, "你好世界")
        XCTAssertTrue(result.translatedText.contains("zh-Hant→en"))
        let saved = try await history.fetchAll(limit: 10)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.translatedText, result.translatedText)
    }

    // MARK: - Validation

    func test_execute_emptyInput_throwsEmptyInputError() async {
        let useCase = DefaultTranslateTextUseCase(
            mtService: MTServiceMock(),
            history: InMemoryHistoryRepository()
        )
        let request = TranslationRequest(
            text: "   ",
            pair: .init(source: .traditionalChinese, target: .english)
        )
        do {
            _ = try await useCase.execute(request)
            XCTFail("Expected emptyInput error")
        } catch let error as TranslationError {
            if case .emptyInput = error { /* ok */ } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_execute_unsupportedPair_throwsUnsupportedPairError() async {
        let useCase = DefaultTranslateTextUseCase(
            mtService: MTServiceMock(),
            history: InMemoryHistoryRepository()
        )
        // 同語言互譯（en → en）不在 MVP 支援清單
        let request = TranslationRequest(
            text: "hello",
            pair: .init(source: .english, target: .english)
        )
        do {
            _ = try await useCase.execute(request)
            XCTFail("Expected unsupportedPair error")
        } catch let error as TranslationError {
            if case .unsupportedPair = error { /* ok */ } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Error propagation

    func test_execute_mtServiceThrows_propagatesError() async {
        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        mt.nextError = .modelNotAvailable
        let useCase = DefaultTranslateTextUseCase(
            mtService: mt,
            history: InMemoryHistoryRepository()
        )
        let request = TranslationRequest(
            text: "hello",
            pair: .init(source: .english, target: .traditionalChinese)
        )
        do {
            _ = try await useCase.execute(request)
            XCTFail("Expected error")
        } catch let error as TranslationError {
            if case .modelNotAvailable = error { /* ok */ } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
