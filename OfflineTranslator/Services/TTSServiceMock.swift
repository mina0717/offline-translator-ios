import Foundation

final class TTSServiceMock: TTSService {
    private(set) var lastSpokenText: String?

    func speak(text: String, language: Language) async throws {
        lastSpokenText = text
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func stop() {
        lastSpokenText = nil
    }
}
