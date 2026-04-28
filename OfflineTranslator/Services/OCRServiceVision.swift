import Foundation
import UIKit
import Vision

// MARK: - ─────────────────────────────────────────────────────────────
// Apple Vision framework 的真實作。
//
// 撰寫日：2026-04-20（草稿可直接在 Mac 驗證）
// v1.2.4：加 recognizeRegions(image:language:) 回傳 bounding box，給 Google Lens 風格疊圖用
// ─────────────────────────────────────────────────────────────

final class VisionOCRService: OCRService {

    /// 長邊上限。超過會先縮圖，避免超大 iPhone 15 Pro 的 48 MP 原圖把 Vision 拖慢。
    /// 實測 2048px 對印刷體辨識率幾乎無損，但速度快 3–5 倍。
    private static let maxLongSide: CGFloat = 2048

    /// v1.2.4：信心度門檻。低於此值的 OCR 結果可能是亂讀（例如 Vision 對土耳其文之類
    /// 不支援的語言會硬猜成中文），疊圖時直接略過避免出現亂碼。
    private static let confidenceThreshold: Float = 0.4

    func recognize(image: UIImage, language: Language) async throws -> [String] {
        let regions = try await recognizeRegions(image: image, language: language)
        let lines = regions.map { $0.text }
        if lines.isEmpty { throw OCRError.noTextFound }
        return lines
    }

    func recognizeRegions(image: UIImage, language: Language) async throws -> [OCRRegion] {
        // 先做 orientation 正規化（相機拍的圖常常 orientation != .up）
        let normalized = image.normalizedForOCR() ?? image
        // 如果太大就縮圖（性能優化）
        let resized = normalized.resizedForOCR(maxLongSide: Self.maxLongSide) ?? normalized
        guard let cgImage = resized.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.underlying(error))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let regions: [OCRRegion] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    // v1.2.4：低信心度直接濾掉，減少疊圖上的亂碼
                    guard candidate.confidence >= Self.confidenceThreshold else { return nil }
                    // Vision 的 boundingBox 是 normalized，原點在左下；轉成左上原點供 UIKit 用
                    let vBox = obs.boundingBox
                    let uBox = CGRect(
                        x: vBox.minX,
                        y: 1 - vBox.maxY,
                        width: vBox.width,
                        height: vBox.height
                    )
                    return OCRRegion(
                        text: trimmed,
                        boundingBox: uBox,
                        confidence: candidate.confidence
                    )
                }

                if regions.isEmpty {
                    continuation.resume(throwing: OCRError.noTextFound)
                } else {
                    continuation.resume(returning: regions)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // 主要語言 + 備援
            request.recognitionLanguages = Self.recognitionLanguages(for: language)

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.underlying(error))
            }
        }
    }

    /// 給 OCR 的候選辨識語言。主要語言放第一位。
    private static func recognitionLanguages(for language: Language) -> [String] {
        switch language {
        case .traditionalChinese: return ["zh-Hant", "en-US"]
        case .english:            return ["en-US", "zh-Hant"]
        }
    }
}

// MARK: - UIImage helper

private extension UIImage {
    /// 把 orientation 正規化為 .up，避免 Vision 拿到歪的圖
    func normalizedForOCR() -> UIImage? {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// 將圖片長邊縮到 `maxLongSide` 以下。若原圖已經比較小就回 self。
    func resizedForOCR(maxLongSide: CGFloat) -> UIImage? {
        let longSide = max(size.width, size.height)
        guard longSide > maxLongSide else { return self }
        let scale = maxLongSide / longSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
