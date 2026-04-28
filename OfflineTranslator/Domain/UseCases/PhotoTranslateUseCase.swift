import Foundation
import UIKit

/// 拍照翻譯 Use Case 介面
/// 流程：UIImage → OCR → 翻譯 → 結果
protocol PhotoTranslateUseCase {
    /// 對圖片做 OCR，回傳偵測到的文字行（每行各自為一個字串）。
    func recognizeText(in image: UIImage, language: Language) async throws -> [String]

    /// v1.2.4：對圖片做 OCR，回傳每塊文字 + bounding box，供 Google Lens 風格疊圖。
    func recognizeRegions(in image: UIImage, language: Language) async throws -> [OCRRegion]

    /// 把 OCR 結果合併並翻譯。
    func translate(lines: [String], pair: LanguagePair) async throws -> TranslationResult

    /// v1.2.4：每塊文字獨立翻譯，譯文回填到 region 上。
    func translateRegions(_ regions: [OCRRegion], pair: LanguagePair) async throws -> [OCRRegion]
}

struct DefaultPhotoTranslateUseCase: PhotoTranslateUseCase {
    let ocrService: OCRService
    let mtService: MTService
    let history: HistoryRepository

    func recognizeText(in image: UIImage, language: Language) async throws -> [String] {
        try await ocrService.recognize(image: image, language: language)
    }

    func recognizeRegions(in image: UIImage, language: Language) async throws -> [OCRRegion] {
        try await ocrService.recognizeRegions(image: image, language: language)
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
        // v1.2.2：fire-and-forget，OCR 翻譯不必等寫歷史
        let toSave = result
        let repo = history
        Task.detached {
            try? await repo.save(toSave)
        }
        return result
    }

    func translateRegions(_ regions: [OCRRegion], pair: LanguagePair) async throws -> [OCRRegion] {
        guard pair.isSupported else { throw TranslationError.unsupportedPair }
        guard !regions.isEmpty else { return [] }

        // 逐塊翻譯。Apple Translation bridge 一次只能跑一個請求，
        // 並行呼叫會互相 cancel；序列跑就好（每塊 < 1s 在 v1.2.2 之後）。
        var out: [OCRRegion] = []
        out.reserveCapacity(regions.count)
        for region in regions {
            let trimmed = region.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                out.append(region)
                continue
            }
            do {
                let translated = try await mtService.translate(text: trimmed, pair: pair)
                var updated = region
                updated.translatedText = translated
                out.append(updated)
            } catch {
                // 單塊失敗不擋整體；該塊保持 nil 譯文，UI 自然只顯示原文
                #if DEBUG
                print("⚠️ region translate failed: \(region.text) → \(error)")
                #endif
                out.append(region)
            }
        }

        // 寫一筆合併 history（fire-and-forget）
        let merged = out.compactMap { $0.translatedText }.joined(separator: "\n")
        let sourceMerged = out.map { $0.text }.joined(separator: "\n")
        if !merged.isEmpty {
            let result = TranslationResult(
                sourceText: sourceMerged,
                translatedText: merged,
                pair: pair,
                createdAt: Date()
            )
            let repo = history
            Task.detached {
                try? await repo.save(result)
            }
        }

        return out
    }
}
