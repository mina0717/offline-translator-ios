import Foundation
import SwiftData

/// 全 App 共用的 SwiftData ModelContainer 建構器。
/// App 啟動時建立一次，透過 `modelContainer(_)` 注入到 SwiftUI 樹中。
enum SwiftDataContainer {

    /// 正式 App 使用的 persistent container。
    /// v1.1：新增 VocabularyEntry schema
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: TranslationRecord.self, VocabularyEntry.self
            )
        } catch {
            fatalError("無法建立 SwiftData ModelContainer: \(error)")
        }
    }()

    /// 測試用：in-memory container（測試不會污染實機資料）。
    static func makeInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TranslationRecord.self, VocabularyEntry.self,
            configurations: config
        )
    }
}
