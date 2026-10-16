import Foundation

final class ASRServiceMock: ASRService {
    var cannedFinalText: String = "你好，這是一段測試語音。"
    /// v1.5.1：模擬「該語言沒有裝置端辨識」
    var supported: Bool = true

    func startRecognition(in language: Language) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard self.supported else {
                continuation.finish(throwing: ASRError.notSupportedOffline(language))
                return
            }
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

    func isSupported(for language: Language) -> Bool { supported }
}
