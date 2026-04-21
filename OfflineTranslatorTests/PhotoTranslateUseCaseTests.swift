import XCTest
import UIKit
@testable import OfflineTranslator

/// UseCase 邊界測試：DefaultPhotoTranslateUseCase
/// 重點：
///   1. recognizeText 直接透傳給 OCRService（錯誤要原封不動）
///   2. translate 對空白、不支援語言對要早期擋下
///   3. translate 成功時會寫 history
///   4. history.save 失敗不應該把 translate 本身弄掛
final class PhotoTranslateUseCaseTests: XCTestCase {

    private func makeImage() -> UIImage {
        // 建一張最小的 1x1 圖，只是要能塞進 UseCase
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    // MARK: - recognizeText

    func test_recognizeText_passesThroughOCRService() async throws {
        let ocr = OCRServiceMock()
        ocr.cannedResult = ["Line A", "Line B"]
        let useCase = DefaultPhotoTranslateUseCase(
            ocrService: ocr,
            mtService: MTServiceMock(),
            history: InMemoryHistoryRepository()
        )

        let lines = try await useCase.recognizeText(in: makeImage(), language: .english)
        XCTAssertEqual(lines, ["Line A", "Line B"])
    }

    func test_recognizeText_ocrError_propagates() async {
        let ocr = OCRServiceMock()
        ocr.nextError = .noTextFound
        let useCase = DefaultPhotoTranslateUseCase(
            ocrService: ocr,
            mtService: MTServiceMock(),
            history: InMemoryHistoryRepository()
        )

        do {
            _ = try await useCase.recognizeText(in: makeImage(), language: .english)
            XCTFail("Expected noTextFound")
        } catch let error as OCRError {
            if case .noTextFound = error { /* ok */ } else {
                XCTFail("Wrong OCRError: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - translate

    func test_translate_happyPath_returnsMergedAndSavesHistory() async throws {
        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        let history = InMemoryHistoryRepository()
        let useCase = DefaultPhotoTranslateUseCase(
            ocrService: OCRServiceMock(),
            mtService: mt,
            history: history
        )

        let result = try await useCase.translate(
            lines: ["Hello", "World"],
            pair: .init(source: .english, target: .traditionalChinese)
        )

        XCTAssertEqual(result.sourceText, "Hello\nWorld")
        XCTAssertTrue(result.translatedText.contains("en→zh-Hant"))

        let saved = try await history.fetchAll(limit: 10)
        XCTAssertEqual(saved.count, 1, "成功的翻譯應該被寫入歷史")
    }

    func test_translate_emptyLines_throwsEmptyInput() async {
        let useCase = DefaultPhotoTranslateUseCase(
            ocrService: OCRServiceMock(),
            mtService: MTServiceMock(),
            history: InMemoryHistoryRepository()
        )
        do {
            _ = try await useCase.translate(
                lines: ["  ", "\n"],
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

    func test_translate_unsupportedPair_throwsUnsupportedPair() async {
        let useCase = DefaultPhotoTranslateUseCase(
            ocrService: OCRServiceMock(),
            mtService: MTServiceMock(),
            history: InMemoryHistoryRepository()
        )
        do {
            _ = try await useCase.translate(
                lines: ["Hello"],
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
        let useCase = DefaultPhotoTranslateUseCase(
            ocrService: OCRServiceMock(),
            mtService: mt,
            history: InMemoryHistoryRepository()
        )
        do {
            _ = try await useCase.translate(
                lines: ["Hello"],
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

    // history.save 失敗不該影響回傳結果：UseCase 用 `try?` 吞掉了
    func test_translate_historySaveFailure_doesNotAffectResult() async throws {
        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        let history = ThrowingHistoryRepository()
        let useCase = DefaultPhotoTranslateUseCase(
            ocrService: OCRServiceMock(),
            mtService: mt,
            history: history
        )

        let result = try await useCase.translate(
            lines: ["Hello"],
            pair: .init(source: .english, target: .traditionalChinese)
        )
        XCTAssertFalse(result.translatedText.isEmpty)
    }
}

// MARK: - Test doubles

/// 永遠 save 失敗的 repo — 用來驗證 UseCase 會吞掉 save 錯誤
private final class ThrowingHistoryRepository: HistoryRepository {
    struct SaveFailure: Error {}

    func save(_ result: TranslationResult) async throws {
        throw SaveFailure()
    }
    func fetchAll(limit: Int?) async throws -> [TranslationResult] { [] }
    func delete(id: UUID) async throws {}
    func clearAll() async throws {}
}
