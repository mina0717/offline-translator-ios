import XCTest
import UIKit
@testable import OfflineTranslator

// MARK: - ─────────────────────────────────────────────────────────────
// PhotoTranslationViewModel 單元測試
//
// 覆蓋項目：
//   1. happy path：process(image:) → recognizedLines 有值、translatedText 有值、phase=.done
//   2. OCR 失敗 → errorMessage 填上、phase=.idle
//   3. swapLanguages：語言互換且觸發重新翻譯
//   4. clear()：重置狀態
// ─────────────────────────────────────────────────────────────
@MainActor
final class PhotoTranslationViewModelTests: XCTestCase {

    private func makeVM(
        ocrLines: [String] = ["Hello", "World"],
        ocrError: OCRError? = nil,
        mtError: TranslationError? = nil
    ) -> (PhotoTranslationViewModel, OCRServiceMock, MTServiceMock) {
        let ocr = OCRServiceMock()
        ocr.cannedResult = ocrLines
        ocr.nextError = ocrError

        let mt = MTServiceMock()
        mt.simulatedLatency = 0
        mt.nextError = mtError

        let history = InMemoryHistoryRepository()
        let useCase = DefaultPhotoTranslateUseCase(
            ocrService: ocr,
            mtService: mt,
            history: history
        )
        let vm = PhotoTranslationViewModel(useCase: useCase)
        return (vm, ocr, mt)
    }

    private func makeDummyImage() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 4, height: 4))
        defer { UIGraphicsEndImageContext() }
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    // MARK: - Happy path

    func test_process_success_fillsRecognizedAndTranslated() async {
        let (vm, _, _) = makeVM(ocrLines: ["Hello", "World"])
        vm.sourceLanguage = .english
        vm.targetLanguage = .traditionalChinese

        await vm.process(image: makeDummyImage())

        XCTAssertEqual(vm.phase, .done)
        XCTAssertEqual(vm.recognizedLines, ["Hello", "World"])
        XCTAssertFalse(vm.translatedText.isEmpty)
        XCTAssertTrue(vm.translatedText.contains("en→zh-Hant"))
        XCTAssertNotNil(vm.pickedImage)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - OCR 失敗

    func test_process_ocrError_setsErrorMessage() async {
        let (vm, _, _) = makeVM(ocrError: .noTextFound)

        await vm.process(image: makeDummyImage())

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.recognizedLines.isEmpty)
        XCTAssertTrue(vm.translatedText.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Merged text

    func test_mergedRecognizedText_joinsLinesWithNewlines() async {
        let (vm, _, _) = makeVM(ocrLines: ["A", "B", "C"])
        await vm.process(image: makeDummyImage())

        XCTAssertEqual(vm.mergedRecognizedText, "A\nB\nC")
    }

    // MARK: - Clear

    func test_clear_resetsState() {
        let (vm, _, _) = makeVM()
        vm.pickedImage = makeDummyImage()
        vm.recognizedLines = ["x"]
        vm.translatedText = "y"
        vm.errorMessage = "err"
        vm.phase = .done

        vm.clear()

        XCTAssertNil(vm.pickedImage)
        XCTAssertTrue(vm.recognizedLines.isEmpty)
        XCTAssertTrue(vm.translatedText.isEmpty)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.phase, .idle)
    }

    // MARK: - Swap

    func test_swapLanguages_togglesLanguages() {
        let (vm, _, _) = makeVM()
        vm.sourceLanguage = .english
        vm.targetLanguage = .traditionalChinese

        vm.swapLanguages()

        XCTAssertEqual(vm.sourceLanguage, .traditionalChinese)
        XCTAssertEqual(vm.targetLanguage, .english)
    }
}
