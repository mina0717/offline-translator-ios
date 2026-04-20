import Foundation

final class ASRServiceMock: ASRService {
    var cannedFinalText: String = "你好，這是一段測試語音。"

    func startRecognition(in language: Language) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let words = cannedFinalText.map { String($0) }
                var acc = ""
                for w in words {
                    acc += w
                    continuation.yield(acc)
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                continuation.finish()
            }
        }
    }

    func stopRecognition() async throws -> String {
        cannedFinalText
    }

    func isSupported(for language: Language) -> Bool { true }
}
