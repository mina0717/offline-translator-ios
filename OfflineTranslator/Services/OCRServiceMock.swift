import Foundation
import UIKit

final class OCRServiceMock: OCRService {
    var cannedResult: [String] = ["Hello World", "This is a mocked OCR line."]
    var nextError: OCRError?

    func recognize(image: UIImage, language: Language) async throws -> [String] {
        if let error = nextError { throw error }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return cannedResult
    }
}
