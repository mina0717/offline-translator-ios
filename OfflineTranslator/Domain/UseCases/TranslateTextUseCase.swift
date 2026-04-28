import Foundation

/// 文字翻譯 Use Case 介面
/// UI / ViewModel 只依賴這個 protocol，方便測試時注入 Mock。
protocol TranslateTextUseCase {
    func execute(_ request: TranslationRequest) async throws -> TranslationResult
}

/// 真實作：呼叫 MTService 並把結果寫入歷史紀錄。
struct DefaultTranslateTextUseCase: TranslateTextUseCase {
    let mtService: MTService
    let history: HistoryRepository

    func execute(_ request: TranslationRequest) async throws -> TranslationResult {
        // 1. 前置檢查
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyInput
        }
        guard request.pair.isSupported else {
            throw TranslationError.unsupportedPair
        }

        // v1.2.6：語言包未下載 → 自動觸發系統下載 sheet
        let status = try await mtService.languagePackStatus(for: request.pair)
        if status != .ready {
            try await mtService.downloadLanguagePack(for: request.pair)
        }

        // 2. 呼叫翻譯引擎
        let translated = try await mtService.translate(
            text: trimmed,
            pair: request.pair
        )

        let result = TranslationResult(
            sourceText: trimmed,
            translatedText: translated,
            pair: request.pair,
            createdAt: Date()
        )

        // 3. 寫入歷史紀錄
        //    v1.2.2：fire-and-forget — translate() 立刻返回，
        //    SwiftData 寫入在背景跑，UI 不會被 context.save() 卡住。
        let toSave = result
        let repo = history
        Task.detached {
            do {
                try await repo.save(toSave)
            } catch {
                #if DEBUG
                print("⚠️ HistoryRepository.save failed: \(error)")
                #endif
            }
        }

        return result
    }
}
