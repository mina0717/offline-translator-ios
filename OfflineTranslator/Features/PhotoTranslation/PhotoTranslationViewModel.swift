import Foundation
import UIKit

/// 拍照翻譯 ViewModel。
///
/// 流程：選圖 / 拍照 → OCR → 翻譯 → 顯示結果（譯文 + 原文行）
///
/// 狀態機：
///   .idle → (選圖) → .processing → .done → (再選圖 / 清除)
///   任一 step 出錯 → .error
@MainActor
final class PhotoTranslationViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case processing
        case done
    }

    // MARK: - Published

    @Published var sourceLanguage: Language = .english
    @Published var targetLanguage: Language = .traditionalChinese
    @Published var pickedImage: UIImage?
    @Published var recognizedLines: [String] = []
    @Published var translatedText: String = ""
    @Published var phase: Phase = .idle
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let useCase: PhotoTranslateUseCase

    init(useCase: PhotoTranslateUseCase) {
        self.useCase = useCase
    }

    // MARK: - Derived

    var isProcessing: Bool { phase == .processing }
    var mergedRecognizedText: String {
        recognizedLines.joined(separator: "\n")
    }
    var currentPair: LanguagePair {
        .init(source: sourceLanguage, target: targetLanguage)
    }
    var availableTargets: [Language] {
        Language.allCases.filter { lang in
            lang != sourceLanguage &&
            LanguagePair.supported.contains(.init(source: sourceLanguage, target: lang))
        }
    }

    // MARK: - Actions

    func swapLanguages() {
        guard !isProcessing else { return }
        let old = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = old
        if !availableTargets.contains(targetLanguage) {
            targetLanguage = availableTargets.first ?? .english
        }
        // 交換後若已有結果，重新翻譯一次
        if pickedImage != nil && !recognizedLines.isEmpty {
            Task { await translateRecognized() }
        }
    }

    /// 使用者挑了一張圖（相機 / 相簿）
    func process(image: UIImage) async {
        errorMessage = nil
        pickedImage = image
        recognizedLines = []
        translatedText = ""
        phase = .processing

        // 1. OCR
        let lines: [String]
        do {
            lines = try await useCase.recognizeText(in: image, language: sourceLanguage)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            phase = .idle
            return
        }
        recognizedLines = lines

        // 2. 翻譯
        await translateRecognized()
    }

    /// 只執行翻譯（語言切換時重用）
    private func translateRecognized() async {
        guard !recognizedLines.isEmpty else {
            phase = .idle
            return
        }
        errorMessage = nil
        phase = .processing
        do {
            let result = try await useCase.translate(
                lines: recognizedLines,
                pair: currentPair
            )
            translatedText = result.translatedText
            phase = .done
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            phase = .idle
        }
    }

    func clear() {
        pickedImage = nil
        recognizedLines = []
        translatedText = ""
        errorMessage = nil
        phase = .idle
    }

    /// 錯誤後的重試：如果已經有 OCR 結果就重翻，否則重跑 OCR + 翻譯
    func retry() async {
        guard let image = pickedImage else { return }
        if recognizedLines.isEmpty {
            await process(image: image)
        } else {
            await translateRecognized()
        }
    }
}
