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

    // MARK: - Dependencies

    private let useCase: TranslateTextUseCase
    private let detector: LanguageDetector

    init(useCase: TranslateTextUseCase, detector: LanguageDetector) {
        self.useCase = useCase
        self.detector = detector
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
    }
}
