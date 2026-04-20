import Foundation
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {

    @Published var records: [TranslationResult] = []

    private let repository: HistoryRepository

    init(repository: HistoryRepository) {
        self.repository = repository
    }

    func reload() async {
        do {
            records = try await repository.fetchAll(limit: 100)
        } catch {
            records = []
        }
    }

    func clearAll() async {
        try? await repository.clearAll()
        await reload()
    }
}
