import SwiftUI

struct VocabularyView: View {
    @EnvironmentObject private var deps: AppDependencies
    @State private var vm: VocabularyViewModel?

    var body: some View {
        ZStack {
            GradientBackground()
            if let vm {
                Content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("生詞本")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vm {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") {
                        Task { await vm.clearAll() }
                    }
                    .disabled(vm.entries.isEmpty)
                }
            }
        }
        .task {
            if vm == nil {
                let v = VocabularyViewModel(repository: deps.vocabularyRepository)
                await v.reload()
                vm = v
            } else {
                await vm?.reload()
            }
        }
    }

    // MARK: - Content

    private struct Content: View {
        @ObservedObject var vm: VocabularyViewModel

        var body: some View {
            VStack(spacing: 0) {
                searchBar
                if vm.entries.isEmpty {
                    empty
                } else {
                    list
                }
            }
        }

        private var searchBar: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextField("字典查詢", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .onSubmit {
                        Task { await vm.reload() }
                    }
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                        Task { await vm.reload() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Capsule().fill(.ultraThinMaterial))
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .onChange(of: vm.searchText) { _, _ in
                Task { await vm.reload() }
            }
        }

        private var empty: some View {
            VStack(spacing: Theme.Spacing.sm) {
                Spacer()
                Image(systemName: "star.square.on.square")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.accent)
                Text("尚無收藏的單字")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("點擊翻譯結果旁的星星就會加入這裡")
                    .font(Theme.Font.caption)
                   .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
        }

        private var list: some View {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(vm.entries, id: \.id) { entry in
                        row(entry)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }

        private func row(_ entry: VocabularyEntry) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(directionText(entry))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Button {
                        Task { await vm.delete(entry) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.7))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                Text(entry.sourceText)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(entry.translatedText)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.accent)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, 2)
                }
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }

        private func directionText(_ entry: VocabularyEntry) -> String {
            "\(flag(for: entry.sourceLanguageCode)) → \(flag(for: entry.targetLanguageCode))"
        }

        private func flag(for code: String) -> String {
            switch code {
            case "zh-Hant": return "🇹🇼"
            case "en":      return "🇺🇸"
            default:        return "🌐"
            }
        }
    }
}

#Preview {
    NavigationStack { VocabularyView() }
        .environmentObject(AppDependencies.makeMock())
}
