import Foundation
import SwiftUI

/// v1.1：生詞本 ViewModel
@MainActor
final class VocabularyViewModel: ObservableObject {

    @Published var entries: [VocabularyEntry] = []
    @Published var searchText: String = ""
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private let repository: VocabularyRepository

    init(repository: VocabularyRepository) {
        self.repository = repository
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let keyword = searchText.trimmingCharacters(in: .whitespaces)
            entries = keyword.isEmpty
                ? try await repository.fetchAll()
                : try await repository.search(keyword: keyword)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func delete(_ entry: VocabularyEntry) async {
        do {
            try await repository.delete(id: entry.id)
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func clearAll() async {
        do {
            try await repository.clearAll()
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
