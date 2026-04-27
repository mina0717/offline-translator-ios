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

    // MARK: - v1.1 fix (Codex review)
    //
    // Bug: `saveToVocabulary()` 原本直接讀 `inputText` / `outputText` / 當前 `langPair`，
    //      但使用者在翻譯完後如果：
    //        - 編輯了 inputText（例如要譯下一句）
    //        - 交換了來源 / 目標語言
    //      這三個欄位就會跟 `outputText` 脫鉤，收藏到生詞本的 entry 變成
    //      「source=新編輯內容、target=舊譯文、pair=新方向」這種錯誤組合。
    //
    // Fix: 成功翻譯後把「source / target / pair」以 immutable snapshot 形式記下來，
    //      `saveToVocabulary()` **只讀 snapshot、不讀 UI state**，並在 clear / swap
    //      時清掉 snapshot 讓收藏按鈕變 disabled。
    //
    // 這也讓 `canSave` 成為可靠的 UI disable 依據。

    /// 最後一次成功翻譯的不可變快照。`saveToVocabulary()` 只信任這個欄位。
    private(set) var lastSnapshot: TranslationResult?

    /// UI 綁定用：snapshot 還在 + 尚未收藏 → 才允許按「收藏」。
    var canSave: Bool {
        lastSnapshot != nil && !isSaved
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

    // MARK: - v1.1.2 Auto-translate (debounced)
    //
    // 使用者反饋：「輸入中文後 要自己手動按翻譯按扭才翻譯，不人性化」
    // 解法：輸入文字後 600ms 沒新增字元就自動翻譯。
    // 避免每打一個字就 fire 一次（會打爆 Translation framework）。

    private var debounceTask: Task<Void, Never>?
    private static let autoTranslateDebounce: UInt64 = 600_000_000  // 600ms

    /// View 監聽 `inputText` 變化時呼叫此方法。
    /// 內部會 cancel 上一個未跑完的 debounce task。
    func onInputChanged() {
        debounceTask?.cancel()
        // 空白 / 純空格不觸發
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            outputText = ""
            errorMessage = nil
            return
        }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoTranslateDebounce)
            guard !Task.isCancelled else { return }
            await self?.translate()
        }
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

        // v1.1 fix: snapshot 只屬於「舊方向 + 舊譯文」，swap 後就失效。
        lastSnapshot = nil
        isSaved = false
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

            // v1.1 fix: 用「發送時」的 request 做 snapshot，確保之後不管 UI 怎麼被改，
            //          收藏進去的永遠是這一輪實際產出的組合。
            lastSnapshot = TranslationResult(
                sourceText: request.text,
                translatedText: result.translatedText,
                pair: request.pair,
                createdAt: .init()
            )
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
        lastSnapshot = nil
    }

    // MARK: - v1.1 Vocabulary integration

    /// 把目前譯文收藏到生詞本。
    /// 若 DictionaryFallbackService 有對應單字條目，順便把定義寫進 note。
    ///
    /// - Important: 這個方法**只讀 `lastSnapshot`**，不讀當下的 inputText / outputText /
    ///   langPair。原因見 file header 的 Codex fix 註解。
    func saveToVocabulary() async {
        guard let vocabulary, let snapshot = lastSnapshot else { return }
        let note = dictionary?
            .lookup(word: snapshot.sourceText, pair: snapshot.pair)?
            .noteSummary ?? ""

        do {
            try await vocabulary.saveFromResult(snapshot, note: note)
            isSaved = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
