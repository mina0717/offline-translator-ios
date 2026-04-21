import Foundation
import UIKit

/// 拍照翻譯 Use Case 介面
/// 流程：UIImage → OCR → 翻譯 → 結果
protocol PhotoTranslateUseCase {
    /// 對圖片做 OCR，回傳偵測到的文字行（每行各自為一個字串）。
    func recognizeText(in image: UIImage, language: Language) async throws -> [String]

    /// 把 OCR 結果合併並翻譯。
    func translate(lines: [String], pair: LanguagePair) async throws -> TranslationResult
}

struct DefaultPhotoTranslateUseCase: PhotoTranslateUseCase {
    let ocrService: OCRService
    let mtService: MTService
    let history: HistoryRepository

    func recognizeText(in image: UIImage, language: Language) async throws -> [String] {
        try await ocrService.recognize(image: image, language: language)
    }

    func translate(lines: [String], pair: LanguagePair) async throws -> TranslationResult {
        let merged = lines.joined(separator: "\n")
        let trimmed = merged.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }
        guard pair.isSupported else  { throw TranslationError.unsupportedPair }

        let translated = try await mtService.translate(text: trimmed, pair: pair)
        let result = TranslationResult(
            sourceText: trimmed,
            translatedText: translated,
            pair: pair,
            createdAt: Date()
        )
        try? await history.save(result)
        return result
    }
}
