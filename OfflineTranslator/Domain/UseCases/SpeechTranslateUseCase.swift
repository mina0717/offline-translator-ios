import Foundation

/// 語音翻譯 Use Case 介面
/// 流程：ASR（語音→文字）→ MT（翻譯）→ TTS（可選，朗讀譯文）
protocol SpeechTranslateUseCase {
    /// 啟動 ASR。回傳逐步的辨識文字（String）流，讓 UI 即時更新。
    /// 真實作應該在使用者鬆開按鈕時 `finish()` 結束串流。
    func startRecognition(in language: Language) -> AsyncThrowingStream<String, Error>

    /// 結束 ASR 並回傳最終辨識結果。
    func stopRecognition() async throws -> String

    /// 將辨識到的文字翻譯。
    func translate(_ text: String, pair: LanguagePair) async throws -> TranslationResult

    /// （可選）朗讀譯文。
    func speak(_ text: String, language: Language) async throws
}

/// 真實作：組合 ASRService / MTService / TTSService。
/// Day 6–7 會實作內部邏輯，現在先放骨架。
struct DefaultSpeechTranslateUseCase: SpeechTranslateUseCase {
    let asrService: ASRService
    let mtService: MTService
    let ttsService: TTSService
    let history: HistoryRepository

    func startRecognition(in language: Language) -> AsyncThrowingStream<String, Error> {
        asrService.startRecognition(in: language)
    }

    func stopRecognition() async throws -> String {
        try await asrService.stopRecognition()
    }

    func translate(_ text: String, pair: LanguagePair) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }
        guard pair.isSupported else  { throw TranslationError.unsupportedPair }

        let translated = try await mtService.translate(text: trimmed, pair: pair)
        let result = TranslationResult(
            sourceText: trimmed,
            translatedText: translated,
            pair: pair,
            createdAt: Date()
        )
        // v1.2.2：fire-and-forget，避免 SwiftData 寫入卡住對話流程
        let toSave = result
        let repo = history
        Task.detached {
            try? await repo.save(toSave)
        }
        return result
    }

    func speak(_ text: String, language: Language) async throws {
        try await ttsService.speak(text: text, language: language)
    }
}
