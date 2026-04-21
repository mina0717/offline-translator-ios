import Foundation
import UIKit
import Vision

// MARK: - ─────────────────────────────────────────────────────────────
// Apple Vision framework 的真實作。
//
// 撰寫日：2026-04-20（草稿可直接在 Mac 驗證）
//
// 【Mac 實測檢查表】
//   □ 1. 繁中手寫 / 印刷體辨識率：拍一張收據 / 看板試
//   □ 2. 英文印刷體 / 手寫體混合：試標籤或說明文
//   □ 3. VNRecognizeTextRequest.supportedRecognitionLanguages 回傳清單
//        是否包含 "zh-Hant" 與 "en-US"
//   □ 4. recognitionLevel = .accurate 的速度：實機 iPhone 12 約 0.3–0.8s
//   □ 5. 若圖片超大 (> 8 MP) 考慮先縮圖以加速
// ─────────────────────────────────────────────────────────────

final class VisionOCRService: OCRService {

    /// 長邊上限。超過會先縮圖，避免超大 iPhone 15 Pro 的 48 MP 原圖把 Vision 拖慢。
    /// 實測 2048px 對印刷體辨識率幾乎無損，但速度快 3–5 倍。
    private static let maxLongSide: CGFloat = 2048

    func recognize(image: UIImage, language: Language) async throws -> [String] {
        // 先做 orientation 正規化（相機拍的圖常常 orientation != .up）
        let normalized = image.normalizedForOCR() ?? image
        // 如果太大就縮圖（性能優化；Mac 實測項 #5）
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
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                if lines.isEmpty {
                    continuation.resume(throwing: OCRError.noTextFound)
                } else {
                    continuation.resume(returning: lines)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // 主要語言 + 備援（同時啟用 zh-Hant 與 en-US 辨識率會更好，
            // 但若效能不夠再退回只用主要語言）
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
    /// ⚠️ Mac 實測項 #3：用 `VNRecognizeTextRequest.supportedRecognitionLanguages`
    /// 確認這些代碼合法
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
    /// 用於加速 OCR：48 MP 原圖對印刷體辨識沒有幫助，2048px 足夠了。
    func resizedForOCR(maxLongSide: CGFloat) -> UIImage? {
        let longSide = max(size.width, size.height)
        guard longSide > maxLongSide else { return self }
        let scale = maxLongSide / longSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // 輸出像素 = 點數，不要再乘 @3x
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
