import Foundation
import SwiftUI

/// 雙向對話一輪。
/// 由「按住哪一邊的麥克風」決定 speaker / listener 對應的語言。
struct ConversationTurn: Identifiable, Hashable {
    let id: UUID
    let speaker: Language
    let listener: Language
    let originalText: String
    /// 譯文。空字串代表「翻譯尚未完成 / 失敗」（可由 `translationError` 區分）。
    var translatedText: String
    /// 翻譯錯誤訊息（v1.2.1）。非 nil 代表這一輪需要重試。
    var translationError: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        speaker: Language,
        listener: Language,
        originalText: String,
        translatedText: String = "",
        translationError: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.speaker = speaker
        self.listener = listener
        self.originalText = originalText
        self.translatedText = translatedText
        self.translationError = translationError
        self.timestamp = timestamp
    }

    var hasError: Bool { translationError != nil }
    var hasTranslation: Bool { !translatedText.isEmpty }
}

/// 雙向對話 ViewModel。
///
/// 設計：
/// - 兩位使用者面對面，左邊（A 角）說 zh-Hant、右邊（B 角）說 en（可在頂部對調）。
/// - 每一邊有一個按住才錄音的大按鈕。同一時刻只能一邊錄音（iOS ASR 限制）。
/// - 錄音放開：ASR → 翻譯成對方語言 → 自動 TTS 朗讀譯文 → 加入對話列表。
///
/// 重用 `SpeechTranslateUseCase`，無需新建 Service。
@MainActor
final class ConversationViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording(speaker: Language)
        case translating(speaker: Language)
        case speaking
    }

    // MARK: - Published

    /// A 角（畫面左側）的語言。預設 zh-Hant。
    @Published var sideALanguage: Language = .traditionalChinese
    /// B 角（畫面右側）的語言。預設 en。
    @Published var sideBLanguage: Language = .english

    /// 對話歷史（依時間順序）
    @Published var turns: [ConversationTurn] = []

    /// 目前 partial 辨識結果（錄音中即時顯示）
    @Published var partialTranscript: String = ""

    /// 當前狀態
    @Published var phase: Phase = .idle

    /// 顯示給使用者看的錯誤
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let useCase: SpeechTranslateUseCase
    private var recognitionTask: Task<Void, Never>?

    init(useCase: SpeechTranslateUseCase) {
        self.useCase = useCase
    }

    /// v1.2.2：避免 task / 麥克風在 ViewModel 已釋放後仍在跑
    deinit {
        recognitionTask?.cancel()
    }

    // MARK: - Derived

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .translating, .speaking: return true
        default: return false
        }
    }

    /// 「現在哪一邊在錄音」(供 View 高亮顯示)
    var recordingSide: Language? {
        if case .recording(let s) = phase { return s }
        return nil
    }

    // MARK: - Actions

    /// 對調兩邊語言。會清空對話歷史，因為翻譯方向變了。
    func swapSides() {
        guard !isRecording && !isBusy else { return }
        // v1.2.2：保險清掉殘留 task（理論上 idle 階段不該有，但避免極端 race）
        recognitionTask?.cancel()
        recognitionTask = nil
        let old = sideALanguage
        sideALanguage = sideBLanguage
        sideBLanguage = old
        turns = []
        partialTranscript = ""
        errorMessage = nil
    }

    /// 按住開始錄音（指定誰在說）
    func startHold(speaker: Language) {
        // 若已在錄音、翻譯、朗讀中，忽略
        guard case .idle = phase else { return }

        // 計算 listener
        let listener: Language = (speaker == sideALanguage) ? sideBLanguage : sideALanguage

        errorMessage = nil
        partialTranscript = ""
        phase = .recording(speaker: speaker)

        recognitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.useCase.startRecognition(in: speaker)
                for try await partial in stream {
                    await MainActor.run { self.partialTranscript = partial }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    self.phase = .idle
                }
            }
        }
        // listener 用 closure 記住，releaseHold 用得到
        self.pendingListener = listener
    }

    /// 放開：停 ASR → 翻譯 → 朗讀 → 加入 turns
    func releaseHold() async {
        guard case .recording(let speaker) = phase else { return }
        let listener = pendingListener ?? otherSide(of: speaker)

        // 1. 停 ASR
        let finalText: String
        do {
            finalText = try await useCase.stopRecognition()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            phase = .idle
            recognitionTask?.cancel()
            return
        }
        recognitionTask?.cancel()

        let trimmed = finalText.isEmpty ? partialTranscript : finalText
        partialTranscript = ""
        guard !trimmed.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase = .idle
            return
        }

        // v1.2.1：先把這一輪以「待翻譯」狀態加入歷史（即使後面翻譯失敗，
        // 使用者也看得到他剛剛說了什麼，可以點「重試」）
        var turn = ConversationTurn(
            speaker: speaker,
            listener: listener,
            originalText: trimmed
        )
        turns.append(turn)
        let turnId = turn.id

        // 2. 翻譯到 listener 語言
        phase = .translating(speaker: speaker)
        let translated: String
        do {
            let pair = LanguagePair(source: speaker, target: listener)
            let result = try await useCase.translate(trimmed, pair: pair)
            translated = result.translatedText
        } catch {
            // 標記這一輪翻譯失敗，UI 會在氣泡內顯示重試按鈕
            let msg = friendlyTranslationError(error)
            updateTurn(id: turnId) { t in
                t.translationError = msg
            }
            phase = .idle
            return
        }

        // 3. 把譯文寫回該 turn
        updateTurn(id: turnId) { t in
            t.translatedText = translated
            t.translationError = nil
        }

        // 4. 朗讀譯文（失敗不影響主流程）
        phase = .speaking
        do {
            try await useCase.speak(translated, language: listener)
        } catch {
            #if DEBUG
            print("⚠️ TTS failed: \(error)")
            #endif
        }
        phase = .idle
    }

    /// 對某一輪重試翻譯（v1.2.1：對話氣泡上「重試」按鈕呼叫）
    func retryTurn(_ turn: ConversationTurn) async {
        guard case .idle = phase else { return }
        let pair = LanguagePair(source: turn.speaker, target: turn.listener)
        // 標記為翻譯中
        updateTurn(id: turn.id) { t in
            t.translationError = nil
        }
        phase = .translating(speaker: turn.speaker)

        let translated: String
        do {
            let result = try await useCase.translate(turn.originalText, pair: pair)
            translated = result.translatedText
        } catch {
            let msg = friendlyTranslationError(error)
            updateTurn(id: turn.id) { t in
                t.translationError = msg
            }
            phase = .idle
            return
        }

        updateTurn(id: turn.id) { t in
            t.translatedText = translated
            t.translationError = nil
        }

        // 重試成功後也朗讀
        phase = .speaking
        do {
            try await useCase.speak(translated, language: turn.listener)
        } catch {
            #if DEBUG
            print("⚠️ TTS failed: \(error)")
            #endif
        }
        phase = .idle
    }

    private func updateTurn(id: UUID, _ mutate: (inout ConversationTurn) -> Void) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        var t = turns[idx]
        mutate(&t)
        turns[idx] = t
    }

    /// 把翻譯錯誤轉成中文使用者看得懂的訊息
    private func friendlyTranslationError(_ error: Error) -> String {
        if (error as NSError).domain == "Swift.CancellationError"
            || error is CancellationError {
            return "翻譯被中斷，請點重試。"
        }
        if let te = error as? TranslationError {
            switch te {
            case .modelNotAvailable:
                return "語言包尚未下載完成，請稍候或到「語言包」頁面下載。"
            case .unsupportedPair:
                return "此語言對暫不支援。"
            case .emptyInput:
                return "未偵測到聲音。"
            case .underlying(let underlying):
                if (underlying as NSError).domain == "Swift.CancellationError"
                    || underlying is CancellationError {
                    return "翻譯被中斷，請點重試。"
                }
                return (te as LocalizedError).errorDescription ?? "翻譯失敗。"
            }
        }
        return (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    /// 重新朗讀某一輪的譯文（點對話氣泡的喇叭）
    func replay(turn: ConversationTurn) async {
        guard case .idle = phase else { return }
        phase = .speaking
        do {
            try await useCase.speak(turn.translatedText, language: turn.listener)
        } catch {
            #if DEBUG
            print("⚠️ TTS failed: \(error)")
            #endif
        }
        phase = .idle
    }

    /// 清空對話歷史
    func clearAll() {
        guard !isRecording && !isBusy else { return }
        turns = []
        partialTranscript = ""
        errorMessage = nil
        phase = .idle
    }

    /// 把錯誤吃掉（點「知道了」用）
    func dismissError() { errorMessage = nil }

    // MARK: - Private helpers

    /// 暫存 listener 語言，避免在 release 時重算（中間使用者可能換邊）。
    private var pendingListener: Language?

    private func otherSide(of speaker: Language) -> Language {
        speaker == sideALanguage ? sideBLanguage : sideALanguage
    }
}
