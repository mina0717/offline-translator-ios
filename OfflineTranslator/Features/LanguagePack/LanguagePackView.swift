import SwiftUI

struct LanguagePackView: View {
    @EnvironmentObject private var deps: AppDependencies
    @State private var vm: LanguagePackViewModel?

    var body: some View {
        ZStack {
            GradientBackground()
            if let vm {
                Content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("語言包")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm == nil {
                let v = LanguagePackViewModel(repository: deps.languagePackRepository)
                await v.reload()
                vm = v
            }
        }
    }

    // MARK: - Content

    private struct Content: View {
        @ObservedObject var vm: LanguagePackViewModel

        var body: some View {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    header
                    ForEach(vm.packs) { pack in
                        row(pack)
                    }
                    footer
                    errorBanner
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
            .refreshable {
                await vm.reload()
            }
            .alert("需要到「設定」操作", isPresented: settingsAlertBinding) {
                Button("打開設定") { vm.openSettings() }
                Button("取消", role: .cancel) { vm.dismissSettingsHint() }
            } message: {
                Text(vm.settingsHint ?? "")
            }
        }

        // MARK: Subviews

        private var header: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("離線語言包")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("下載完成後，文字 / 語音 / 拍照翻譯都能在離線時使用。")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        private func row(_ pack: LanguagePackInfo) -> some View {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pairTitle(pack.pair))
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    HStack(spacing: 6) {
                        statusIcon(for: pack.status)
                        Text(statusText(for: pack))
                            .font(Theme.Font.caption)
                            .foregroundStyle(statusColor(for: pack.status))
                    }
                    Text("約 \(pack.estimatedSizeMB) MB · 離線可用")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                // 把資訊區塊合併為單一 VoiceOver 元素，
                // 按鈕仍維持獨立可點（不被包含在這個 accessibility group 裡）
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: pack))
                Spacer()
                actionButton(for: pack)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .glassCard()
        }

        private var footer: some View {
            VStack(spacing: Theme.Spacing.xs) {
                Text("MVP 範圍：中⇄英")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("下載：iOS 會顯示系統對話框，確認後自動下載。")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("刪除：需到「設定 → 一般 → 語言與地區 → 翻譯」手動移除。")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Theme.Spacing.md)
        }

        @ViewBuilder
        private var errorBanner: some View {
            if let msg = vm.errorMessage {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        vm.dismissError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Color.red.opacity(0.08))
                )
            }
        }

        @ViewBuilder
        private func actionButton(for pack: LanguagePackInfo) -> some View {
            let isDownloadingThis = vm.downloadingPair == pack.pair

            switch pack.status {
            case .ready:
                Button {
                    Task { await vm.remove(pack.pair) }
                } label: {
                    Label("刪除", systemImage: "trash")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel(actionAccessibilityLabel(for: pack))

            case .downloading:
                ProgressView()
                    .accessibilityLabel(actionAccessibilityLabel(for: pack))

            case .notDownloaded, .failed:
                if isDownloadingThis {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("等候中…")
                            .font(Theme.Font.caption)
                    }
                    .accessibilityLabel("下載等候中")
                } else {
                    Button {
                        Task { await vm.download(pack.pair) }
                    } label: {
                        Label("下載", systemImage: "arrow.down.circle")
                            .font(Theme.Font.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accent)
                    .disabled(vm.downloadingPair != nil)
                    .accessibilityLabel(actionAccessibilityLabel(for: pack))
                }
            }
        }

        // MARK: Helpers

        private func pairTitle(_ pair: LanguagePair) -> String {
            "\(pair.source.flag) \(pair.source.displayName) → \(pair.target.flag) \(pair.target.displayName)"
        }

        /// VoiceOver 讀出整張 row 的文字：不帶 emoji，只念內容
        private func accessibilityLabel(for pack: LanguagePackInfo) -> String {
            let direction = "\(pack.pair.source.displayName)翻譯成\(pack.pair.target.displayName)"
            let statusPhrase: String
            switch pack.status {
            case .notDownloaded: statusPhrase = "尚未下載"
            case .downloading(let p): statusPhrase = "下載中 \(Int(p * 100)) 趴"
            case .ready: statusPhrase = "已下載，可離線使用"
            case .failed: statusPhrase = "下載失敗"
            }
            return "\(direction)，\(statusPhrase)，約 \(pack.estimatedSizeMB) 百萬位元組"
        }

        /// 給動作按鈕的 a11y 標籤（VoiceOver 才會聽到完整語言對）
        private func actionAccessibilityLabel(for pack: LanguagePackInfo) -> String {
            let direction = "\(pack.pair.source.displayName)到\(pack.pair.target.displayName)"
            switch pack.status {
            case .ready: return "刪除\(direction)語言包"
            case .notDownloaded, .failed: return "下載\(direction)語言包"
            case .downloading: return "\(direction)語言包下載中"
            }
        }

        private func statusText(for pack: LanguagePackInfo) -> String {
            switch pack.status {
            case .notDownloaded:           return "未下載"
            case .downloading(let p):      return "下載中 \(Int(p * 100))%"
            case .ready:                   return "已下載"
            case .failed(let msg):         return "失敗：\(msg)"
            }
        }

        private func statusColor(for status: LanguagePackStatus) -> Color {
            switch status {
            case .notDownloaded: return Theme.Colors.textSecondary
            case .downloading:   return Theme.Colors.accent
            case .ready:         return .green
            case .failed:        return .red
            }
        }

        @ViewBuilder
        private func statusIcon(for status: LanguagePackStatus) -> some View {
            switch status {
            case .ready:
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .downloading:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Theme.Colors.accent)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .notDownloaded:
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }

        private var settingsAlertBinding: Binding<Bool> {
            Binding(
                get: { vm.settingsHint != nil },
                set: { if !$0 { vm.dismissSettingsHint() } }
            )
        }
    }
}

#Preview {
    NavigationStack { LanguagePackView() }
        .environmentObject(AppDependencies.makeMock())
}
