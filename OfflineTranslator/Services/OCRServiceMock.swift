import Foundation
import UIKit

final class OCRServiceMock: OCRService {
    var cannedResult: [String] = ["Hello World", "This is a mocked OCR line."]
    var cannedRegions: [OCRRegion] = [
        OCRRegion(text: "Hello World", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.08), confidence: 0.95),
        OCRRegion(text: "This is a mocked OCR line.", boundingBox: CGRect(x: 0.1, y: 0.25, width: 0.6, height: 0.06), confidence: 0.9)
    ]
    var nextError: OCRError?

    func recognize(image: UIImage, language: Language) async throws -> [String] {
        if let error = nextError { throw error }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return cannedResult
    }

    func recognizeRegions(image: UIImage, language: Language) async throws -> [OCRRegion] {
        if let error = nextError { throw error }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return cannedRegions
    }
}
