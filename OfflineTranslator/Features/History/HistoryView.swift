import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var deps: AppDependencies
    @State private var vm: HistoryViewModel?

    var body: some View {
        ZStack {
            GradientBackground()
            if let vm {
                Content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("歷史紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vm {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") {
                        Task { await vm.clearAll() }
                    }
                    .disabled(vm.records.isEmpty)
                }
            }
        }
        .task {
            if vm == nil {
                let v = HistoryViewModel(repository: deps.historyRepository)
                await v.reload()
                vm = v
            } else {
                await vm?.reload()
            }
        }
    }

    private struct Content: View {
        @ObservedObject var vm: HistoryViewModel

        var body: some View {
            if vm.records.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(vm.records, id: \.self) { record in
                            row(record)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                }
            }
        }

        private var empty: some View {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "clock")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.accent)
                Text("尚無翻譯紀錄")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("完成第一次翻譯後會出現在這裡")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }

        private func row(_ r: TranslationResult) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(r.pair.source.flag) → \(r.pair.target.flag)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(r.sourceText)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(r.translatedText)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.accent)
                Text(r.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }
}

#Preview {
    NavigationStack { HistoryView() }
        .environmentObject(AppDependencies.makeMock())
}
