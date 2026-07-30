import Foundation
import SwiftUI

/// v1.5.0：免持聆聽模式的一句話。
struct ListeningLine: Identifiable, Equatable {
    let id: UUID
    let originalText: String
    var translatedText: String
    var errorMessage: String?
    let timestamp: Date

    init(id: UUID = UUID(),
         originalText: String,
         translatedText: String = "",
         errorMessage: String? = nil,
         timestamp: Date = Date()) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.errorMessage = errorMessage
        self.timestamp = timestamp
    }

    var hasTranslation: Bool { !translatedText.isEmpty }
}

/// v1.5.0：**主畫面的免持聆聽模式** ViewModel。
///
/// 與「雙向對話裡的免持」的差別：
/// - 雙向對話：畫面上下對切，兩個人面對面各看各的。
/// - 這一頁：**不分割**。使用者用耳朵聽對方講話、用眼睛看畫面上的譯文。
///   典型場景是聽演講、聽導覽、聽對方講一長段。
///
/// 所以這裡的排版是「單向、由上往下、字要大」，
/// 不需要 speaker/listener 兩邊的概念。
@MainActor
final class HandsFreeListeningViewModel: ObservableObject {

    // MARK: - Published

    /// 對方講的語言（要被辨識的）
    @Published var sourceLanguage: Language = .english {
        didSet { if oldValue != sourceLanguage { handleLanguageChange() } }
    }
    /// 我要讀的語言（譯文）
    @Published var targetLanguage: Language = .traditionalChinese {
        didSet { if oldValue != targetLanguage { preheat() } }
    }

    @Published private(set) var lines: [ListeningLine] = []
    /// 正在辨識中、還沒定案的文字
    @Published private(set) var partialText: String = ""
    @Published private(set) var isListening = false
    @Published private(set) var isHearingSpeech = false
    @Published private(set) var micLevel: Float = -100
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let service: HandsFreeASRService
    private let useCase: SpeechTranslateUseCase

    private var listenTask: Task<Void, Never>?
    /// 序列翻譯佇列 —— AppleTranslationBridge 單 continuation，併發會互相取消
    private var pendingIDs: [UUID] = []
    private var isDraining = false

    init(service: HandsFreeASRService, useCase: SpeechTranslateUseCase) {
        self.service = service
        self.useCase = useCase
        preheat()
    }

    deinit { listenTask?.cancel() }

    // MARK: - Derived

    var availableTargets: [Language] {
        Language.allCases.filter { $0 != sourceLanguage }
    }

    /// 該語言能不能免持（需支援離線辨識）
    var canListenToSource: Bool {
        service.supportsOnDevice(sourceLanguage)
    }

    var isEmpty: Bool { lines.isEmpty && partialText.isEmpty }

    // MARK: - Actions

    func toggleListening() {
        isListening ? stop() : start()
    }

    func start() {
        guard !isListening else { return }

        guard service.supportsOnDevice(sourceLanguage) else {
            errorMessage = String(
                format: String(localized: "handsfree.error.no_offline_asr"),
                sourceLanguage.displayName
            )
            return
        }

        errorMessage = nil
        partialText = ""
        isListening = true

        let source = sourceLanguage
        let target = targetLanguage

        listenTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.start(language: source)
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.stop()
                return
            }

            for await event in self.service.events {
                if Task.isCancelled { return }
                switch event {
                case .partial(let text):
                    self.partialText = text

                case .finalized(let text):
                    self.partialText = ""
                    self.isHearingSpeech = false
                    self.enqueue(text: text, source: source, target: target)

                case .level(let db):
                    self.micLevel = db

                case .speechStarted:
                    self.isHearingSpeech = true

                case .recoverableError:
                    // 服務會自己換一輪，不打斷使用者
                    break
                }
            }
        }
    }

    func stop() {
        listenTask?.cancel(); listenTask = nil
        service.stop()
        isListening = false
        isHearingSpeech = false
        micLevel = -100
        partialText = ""
    }

    func clearAll() {
        guard !isListening else { return }
        lines.removeAll()
        pendingIDs.removeAll()
        partialText = ""
    }

    /// 對某一句重試翻譯
    func retry(_ line: ListeningLine) {
        guard let idx = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[idx].errorMessage = nil
        pendingIDs.append(line.id)
        drainQueue()
    }

    // MARK: - Private

    private func handleLanguageChange() {
        // 換了要聽的語言就得重開辨識器（一個辨識器只綁一種語言）
        if isListening {
            stop()
            start()
        }
        preheat()
    }

    private func preheat() {
        let pair = LanguagePair(source: sourceLanguage, target: targetLanguage)
        Task.detached { [useCase] in
            await useCase.preheatLanguagePack(pair: pair)
        }
    }

    private func enqueue(text: String, source: Language, target: Language) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let line = ListeningLine(originalText: trimmed)
        lines.append(line)
        pendingIDs.append(line.id)
        drainQueue()
    }

    /// **一次只翻一句** —— 見 `pendingIDs` 的說明
    private func drainQueue() {
        guard !isDraining else { return }
        isDraining = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isDraining = false }

            while !self.pendingIDs.isEmpty {
                if Task.isCancelled { return }
                let id = self.pendingIDs.removeFirst()
                guard let line = self.lines.first(where: { $0.id == id }) else { continue }

                let pair = LanguagePair(source: self.sourceLanguage, target: self.targetLanguage)
                do {
                    let result = try await self.useCase.translate(line.originalText, pair: pair)
                    self.update(id: id) { l in
                        l.translatedText = result.translatedText
                        l.errorMessage = nil
                    }
                } catch {
                    self.update(id: id) { l in
                        l.errorMessage = String(localized: "handsfree.line.translate_failed")
                    }
                }
            }
        }
    }

    private func update(id: UUID, _ mutate: (inout ListeningLine) -> Void) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        var l = lines[idx]
        mutate(&l)
        lines[idx] = l
    }
}
