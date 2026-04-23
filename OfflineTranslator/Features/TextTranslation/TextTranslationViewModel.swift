import Foundation
import SwiftUI

@MainActor
final class TextTranslationViewModel: ObservableObject {

    // MARK: - Published state

    @Published var inputText: String = ""
    @Published var outputText: String = ""
    @Published var sourceLanguage: Language = .traditionalChinese
    @Published var targetLanguage: Language = .english
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// v1.1：這一輪翻譯是否已被收藏到生詞本
    @Published var isSaved: Bool = false

    /// v1.1：目前輸入/輸出是否可以收藏（非空 + 尚未收藏 + 非 loading）
    /// 用計算屬性追蹤，不需要額外的 @Published 欄位。
    var canSave: Bool {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedInput.isEmpty
            && !trimmedOutput.isEmpty
            && !isSaved
            && !isLoading
    }

    // MARK: - Dependencies

    private let useCase: TranslateTextUseCase
    private let detector: LanguageDetector
    /// v1.1：生詞本（可選，舊測試可傳 nil）
    private let vocabulary: VocabularyRepository?
    /// v1.1：字典 fallback（可選，用來在 MT 翻得很怪時補充 note）
    private let dictionary: DictionaryLookupService?

    init(
        useCase: TranslateTextUseCase,
        detector: LanguageDetector,
        vocabulary: VocabularyRepository? = nil,
        dictionary: DictionaryLookupService? = nil
    ) {
        self.useCase = useCase
        self.detector = detector
        self.vocabulary = vocabulary
        self.dictionary = dictionary
    }

    // MARK: - Public

    /// MVP 支援的目標語言（依目前 source 切換）。
    var availableTargets: [Language] {
        Language.allCases.filter { lang in
            lang != sourceLanguage &&
            LanguagePair.supported.contains(.init(source: sourceLanguage, target: lang))
        }
    }

    /// 交換來源 / 目標語言。
    func swapLanguages() {
        let oldSource = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = oldSource

        // 順手把 output 變回 input，方便連續對話
        if !outputText.isEmpty {
            inputText = outputText
            outputText = ""
        }

        // 切換後若 target 不在合法清單，自動補一個
        if !availableTargets.contains(targetLanguage) {
            targetLanguage = availableTargets.first ?? .english
        }
    }

    /// 自動偵測來源語言（觸發於使用者明確點按鈕，不要自動跑以免干擾打字）。
    func autoDetectSource() {
        guard let detected = detector.detect(inputText) else { return }
        sourceLanguage = detected
        if !availableTargets.contains(targetLanguage) {
            targetLanguage = availableTargets.first ?? .english
        }
    }

    /// 主要動作：執行翻譯。
    func translate() async {
        errorMessage = nil
        let request = TranslationRequest(
            text: inputText,
            pair: .init(source: sourceLanguage, target: targetLanguage)
        )
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await useCase.execute(request)
            outputText = result.translatedText
            isSaved = false         // 新的一輪譯文預設未收藏
        } catch let error as TranslationError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 清空欄位。
    func clear() {
        inputText = ""
        outputText = ""
        errorMessage = nil
        isSaved = false
    }

    // MARK: - v1.1 Vocabulary integration

    /// 把目前譯文收藏到生詞本。
    /// 若 DictionaryFallbackService 有對應單字條目，順便把定義寫進 note。
    func saveToVocabulary() async {
        guard let vocabulary else { return }
        let src = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tgt = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty, !tgt.isEmpty else { return }

        let pair = LanguagePair(source: sourceLanguage, target: targetLanguage)
        let note = dictionary?.lookup(word: src, pair: pair)?.noteSummary ?? ""

        let result = TranslationResult(
            sourceText: src,
            translatedText: tgt,
            pair: pair,
            createdAt: .init()
        )
        do {
            try await vocabulary.saveFromResult(result, note: note)
            isSaved = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
