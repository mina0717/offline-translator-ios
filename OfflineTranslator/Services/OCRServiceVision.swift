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

    func recognize(image: UIImage, language: Language) async throws -> [String] {
        // 先做 orientation 正規化（相機拍的圖常常 orientation != .up）
        let normalized = image.normalizedForOCR() ?? image
        guard let cgImage = normalized.cgImage else {
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
}
