import Foundation
import UIKit

/// 拍照翻譯 ViewModel（v1.2.4：Google Lens 風格疊圖）
///
/// 流程：選圖 / 拍照 → OCR（含 bounding box）→ 每塊獨立翻譯 → 疊在原圖上
///
/// 狀態機：
///   .idle → (選圖) → .recognizing → .translating → .done
///   錯誤 → .error
@MainActor
final class PhotoTranslationViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recognizing
        case translating
        case done
    }

    // MARK: - Published

    @Published var sourceLanguage: Language = .english
    @Published var targetLanguage: Language = .traditionalChinese
    @Published var pickedImage: UIImage?
    /// v1.2.4：每塊文字 + bounding box + 譯文（疊圖渲染用）
    @Published var regions: [OCRRegion] = []
    @Published var phase: Phase = .idle
    @Published var errorMessage: String?
    /// v1.2.4：使用者切換「原文 / 譯文 / 並列」三種顯示模式
    @Published var displayMode: DisplayMode = .overlay

    enum DisplayMode: String, CaseIterable, Identifiable {
        /// 原圖蓋上譯文（Google Lens 預設）
        case overlay = "譯文疊圖"
        /// 顯示原圖（不蓋）
        case original = "只看原圖"
        /// 列表並列原文與譯文
        case list = "原文 / 譯文 並列"
        var id: String { rawValue }
    }

    // MARK: - Dependencies

    private let useCase: PhotoTranslateUseCase

    init(useCase: PhotoTranslateUseCase) {
        self.useCase = useCase
    }

    // MARK: - Derived

    var isProcessing: Bool { phase == .recognizing || phase == .translating }
    var hasResults: Bool { !regions.isEmpty }
    /// 合併原文（給「儲存到歷史 / 分享」用）
    var mergedSourceText: String { regions.map { $0.text }.joined(separator: "\n") }
    /// 合併譯文
    var mergedTranslatedText: String {
        regions.compactMap { $0.translatedText }.joined(separator: "\n")
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
        // 交換後若已有結果，重新翻譯一次（OCR 結果不變）
        if pickedImage != nil && !regions.isEmpty {
            Task { await translateExistingRegions() }
        }
    }

    /// 使用者挑了一張圖（相機 / 相簿）
    func process(image: UIImage) async {
        errorMessage = nil
        pickedImage = image
        regions = []
        phase = .recognizing

        // 1. OCR + bbox
        let detected: [OCRRegion]
        do {
            detected = try await useCase.recognizeRegions(in: image, language: sourceLanguage)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            phase = .idle
            return
        }
        regions = detected

        // 2. 每塊獨立翻譯
        await translateExistingRegions()
    }

    /// 沿用現有 regions，重新翻譯（語言切換 / 重試用）
    private func translateExistingRegions() async {
        guard !regions.isEmpty else {
            phase = .idle
            return
        }
        errorMessage = nil
        phase = .translating
        do {
            let translated = try await useCase.translateRegions(regions, pair: currentPair)
            regions = translated
            phase = .done
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            phase = .idle
        }
    }

    func clear() {
        pickedImage = nil
        regions = []
        errorMessage = nil
        phase = .idle
    }

    /// 錯誤後的重試
    func retry() async {
        guard let image = pickedImage else { return }
        if regions.isEmpty {
            await process(image: image)
        } else {
            await translateExistingRegions()
        }
    }
}
