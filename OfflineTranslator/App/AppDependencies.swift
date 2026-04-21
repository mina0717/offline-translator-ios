import Foundation
import SwiftData

/// 全 App 共用的依賴注入容器。
/// 方便在「開發 / 測試 / 真機」之間切換真實作與 Mock。
@MainActor
final class AppDependencies: ObservableObject {

    // Services
    let mtService: MTService
    let ocrService: OCRService
    let asrService: ASRService
    let ttsService: TTSService
    let languageDetector: LanguageDetector

    // Data
    let modelContainer: ModelContainer
    let historyRepository: HistoryRepository
    let languagePackRepository: LanguagePackRepository
    let vocabularyRepository: VocabularyRepository
    let dictionaryService: DictionaryLookupService

    // Use Cases
    let translateTextUseCase: TranslateTextUseCase
    let speechTranslateUseCase: SpeechTranslateUseCase
    let photoTranslateUseCase: PhotoTranslateUseCase
    let modelManager: ModelManager

    // MARK: - Factories

    /// 預設（真機）組裝：走 Apple Translation / Vision / Speech / AVSpeechSynthesizer。
    static func makeDefault() -> AppDependencies {
        let container = SwiftDataContainer.shared
        let history = SwiftDataHistoryRepository(container: container)
        let vocab = SwiftDataVocabularyRepository(container: container)

        let mt  = AppleMTService()
        let ocr = VisionOCRService()
        let asr = SpeechASRService()
        let tts = AVFoundationTTSService()
        let detector = LanguageDetector()

        let modelMgr = DefaultModelManager(mtService: mt)
        let packRepo = DefaultLanguagePackRepository(modelManager: modelMgr)

        return AppDependencies(
            mtService: mt,
            ocrService: ocr,
            asrService: asr,
            ttsService: tts,
            languageDetector: detector,
            modelContainer: container,
            historyRepository: history,
            languagePackRepository: packRepo,
            vocabularyRepository: vocab,
            dictionaryService: DictionaryFallbackService.shared,
            translateTextUseCase: DefaultTranslateTextUseCase(
                mtService: mt, history: history
            ),
            speechTranslateUseCase: DefaultSpeechTranslateUseCase(
                asrService: asr, mtService: mt, ttsService: tts, history: history
            ),
            photoTranslateUseCase: DefaultPhotoTranslateUseCase(
                ocrService: ocr, mtService: mt, history: history
            ),
            modelManager: modelMgr
        )
    }

    /// 全 Mock 組裝：UI 原型 / preview / 單元測試用。
    /// 文字翻譯走得通，可以端到端驗 UI/UseCase/Data 層。
    static func makeMock() -> AppDependencies {
        let container = (try? SwiftDataContainer.makeInMemory()) ?? SwiftDataContainer.shared
        let history = SwiftDataHistoryRepository(container: container)
        let vocab = InMemoryVocabularyRepository()

        let mt  = MTServiceMock()
        let ocr = OCRServiceMock()
        let asr = ASRServiceMock()
        let tts = TTSServiceMock()
        let detector = LanguageDetector()

        let modelMgr = DefaultModelManager(mtService: mt)
        let packRepo = DefaultLanguagePackRepository(modelManager: modelMgr)

        return AppDependencies(
            mtService: mt,
            ocrService: ocr,
            asrService: asr,
            ttsService: tts,
            languageDetector: detector,
            modelContainer: container,
            historyRepository: history,
            languagePackRepository: packRepo,
            vocabularyRepository: vocab,
            dictionaryService: DictionaryFallbackService.shared,
            translateTextUseCase: DefaultTranslateTextUseCase(
                mtService: mt, history: history
            ),
            speechTranslateUseCase: DefaultSpeechTranslateUseCase(
                asrService: asr, mtService: mt, ttsService: tts, history: history
            ),
            photoTranslateUseCase: DefaultPhotoTranslateUseCase(
                ocrService: ocr, mtService: mt, history: history
            ),
            modelManager: modelMgr
        )
    }

    // MARK: - Private init

    private init(
        mtService: MTService,
        ocrService: OCRService,
        asrService: ASRService,
        ttsService: TTSService,
        languageDetector: LanguageDetector,
        modelContainer: ModelContainer,
        historyRepository: HistoryRepository,
        languagePackRepository: LanguagePackRepository,
        vocabularyRepository: VocabularyRepository,
        dictionaryService: DictionaryLookupService,
        translateTextUseCase: TranslateTextUseCase,
        speechTranslateUseCase: SpeechTranslateUseCase,
        photoTranslateUseCase: PhotoTranslateUseCase,
        modelManager: ModelManager
    ) {
        self.mtService = mtService
        self.ocrService = ocrService
        self.asrService = asrService
        self.ttsService = ttsService
        self.languageDetector = languageDetector
        self.modelContainer = modelContainer
        self.historyRepository = historyRepository
        self.languagePackRepository = languagePackRepository
        self.vocabularyRepository = vocabularyRepository
        self.dictionaryService = dictionaryService
        self.translateTextUseCase = translateTextUseCase
        self.speechTranslateUseCase = speechTranslateUseCase
        self.photoTranslateUseCase = photoTranslateUseCase
        self.modelManager = modelManager
    }
}
