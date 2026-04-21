import Foundation

/// 語言包資料源（這個 MVP 直接代理 ModelManager）。
/// 之所以還留一個 Repository，是為了未來若要加入「自家 CDN 額外字典」時
/// 有個獨立 layer 不會把 UseCase 改爛。
protocol LanguagePackRepository {
    func list() async -> [LanguagePackInfo]
    func download(pair: LanguagePair) async throws
    func remove(pair: LanguagePair) async throws
}

struct LanguagePackInfo: Identifiable, Hashable {
    var id: LanguagePair { pair }
    let pair: LanguagePair
    let status: LanguagePackStatus
    let estimatedSizeMB: Int
}

struct DefaultLanguagePackRepository: LanguagePackRepository {
    let modelManager: ModelManager

    func list() async -> [LanguagePackInfo] {
        var result: [LanguagePackInfo] = []
        for pair in LanguagePair.supported {
            let status = await modelManager.status(for: pair)
            result.append(.init(
                pair: pair,
                status: status,
                estimatedSizeMB: modelManager.estimatedSize(for: pair)
            ))
        }
        return result
    }

    func download(pair: LanguagePair) async throws {
        try await modelManager.download(pair: pair)
    }

    func remove(pair: LanguagePair) async throws {
        try await modelManager.remove(pair: pair)
    }
}
