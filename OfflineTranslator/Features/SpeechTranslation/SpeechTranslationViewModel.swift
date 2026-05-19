import Foundation
import SwiftUI

/// 語音翻譯 ViewModel。
///
/// 流程：按住麥克風 → ASR partial 顯示 → 放開 → translate → 自動 TTS 播譯文。
///
/// 狀態機：
///   .idle → (按下) → .recording → (放開) → .translating → .done → (點再播) → .speaking
///   任一 step 出錯 → .idle + errorMessage
@MainActor
final class SpeechTranslationViewModel: ObservableObject {

    // MARK: - State enum

    enum Phase: Equatable {
        case idle
        case recording
        case translating
        case done
        case speaking
    }

    // MARK: - Published state

    @Published var sourceLanguage: Language = .traditionalChinese
    @Published var targetLanguage: Language = .english
    @Published var phase: Phase = .idle
    @Published var partialTranscript: String = ""
    @Published var finalTranscript: String = ""
    @Published var translatedText: String = ""
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let useCase: SpeechTranslateUseCase
    private var recognitionTask: Task<Void, Never>?

    init(useCase: SpeechTranslateUseCase) {
        self.useCase = useCase
        // v1.3.0：開頁就背景預下載預設 pair（zh-Hant ↔ en），避免使用者第一次按麥克風才等下載
        preheatCurrentPair()
    }

    /// v1.3.0：把當前 source/target pair 丟給 useCase 背景下載（不阻塞 UI）
    private func preheatCurrentPair() {
        let pair = currentPair
        Task.detached { [useCase] in
            await useCase.preheatLanguagePack(pair: pair)
        }
    }

    // MARK: - Derived

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase == .translating || phase == .speaking }

    var currentPair: LanguagePair {
        .init(source: sourceLanguage, target: targetLanguage)
    }

    /// 可選的目標語言（排除 source 本身與不支援的組合）
    var availableTargets: [Language] {
        Language.allCases.filter { lang in
            lang != sourceLanguage &&
            LanguagePair.supported.contains(.init(source: sourceLanguage, target: lang))
        }
    }

    // MARK: - Actions

    func swapLanguages() {
        guard !isBusy && !isRecording else { return }
        let old = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = old
        if !availableTargets.contains(targetLanguage) {
            targetLanguage = availableTargets.first ?? .english
        }
        // 交換後清空上一輪結果
        partialTranscript = ""
        finalTranscript = ""
        translatedText = ""
        errorMessage = nil
        preheatCurrentPair()
    }

    /// v1.3.0：使用者透過 Menu picker 選來源語言。若新 source 與 target 相同，自動換 target。
    func setSource(_ lang: Language) {
        guard !isBusy && !isRecording else { return }
        guard sourceLanguage != lang else { return }
        sourceLanguage = lang
        if targetLanguage == sourceLanguage || !availableTargets.contains(targetLanguage) {
            targetLanguage = availableTargets.first ?? .english
        }
        partialTranscript = ""
        finalTranscript = ""
        translatedText = ""
        errorMessage = nil
        preheatCurrentPair()
    }

    /// v1.3.0：使用者透過 Menu picker 選目標語言。
    func setTarget(_ lang: Language) {
        guard !isBusy && !isRecording else { return }
        guard targetLanguage != lang, lang != sourceLanguage else { return }
        targetLanguage = lang
        translatedText = ""
        errorMessage = nil
        preheatCurrentPair()
    }

    /// 長按開始：啟動 ASR 串流
    func startHold() {
        guard phase == .idle || phase == .done else { return }
        errorMessage = nil
        partialTranscript = ""
        finalTranscript = ""
        translatedText = ""
        phase = .recording

        let lang = sourceLanguage
        recognitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.useCase.startRecognition(in: lang)
                for try await partial in stream {
                    await MainActor.run {
                        self.partialTranscript = partial
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    self.phase = .idle
                }
            }
        }
    }

    /// 放開結束：停 ASR → 翻譯 → TTS
    func releaseHold() async {
        guard phase == .recording else { return }

        // 1. 停止 ASR，取得 final transcript
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
        finalTranscript = finalText.isEmpty ? partialTranscript : finalText

        // 無內容：直接回 idle，不翻譯
        guard !finalTranscript.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase = .idle
            return
        }

        // 2. 翻譯
        phase = .translating
        do {
            let result = try await useCase.translate(finalTranscript, pair: currentPair)
            translatedText = result.translatedText
            phase = .done
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            phase = .idle
            return
        }

        // v1.2.9：取消自動朗讀。使用者反饋翻譯後突然發聲嚇人。
        // 改由使用者點譯文旁的喇叭 icon 觸發 speakTranslation()。
    }

    /// 手動點譯文旁的喇叭
    func speakTranslation() async {
        guard !translatedText.isEmpty else { return }
        let text = translatedText
        let lang = targetLanguage
        phase = .speaking
        do {
            try await useCase.speak(text, language: lang)
        } catch {
            // TTS 失敗不影響主流程，只記 log
            #if DEBUG
            print("⚠️ TTS failed: \(error)")
            #endif
        }
        phase = .done
    }

    func clear() {
        guard !isBusy && !isRecording else { return }
        partialTranscript = ""
        finalTranscript = ""
        translatedText = ""
        errorMessage = nil
        phase = .idle
    }

    /// 翻譯失敗後的重試：如果還留著 finalTranscript 就重翻一次，
    /// 不用再讓使用者重錄。
    func retryTranslation() async {
        guard !finalTranscript.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !isRecording && phase != .translating else { return }
        errorMessage = nil
        phase = .translating
        do {
            let result = try await useCase.translate(finalTranscript, pair: currentPair)
            translatedText = result.translatedText
            phase = .done
            await speakTranslation()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            phase = .idle
        }
    }

    /// 單純把錯誤訊息吃掉（點「知道了」用）
    func dismissError() {
        errorMessage = nil
    }
}
