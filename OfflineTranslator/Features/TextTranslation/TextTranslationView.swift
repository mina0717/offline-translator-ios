import SwiftUI
import UIKit   // UIPasteboard

struct TextTranslationView: View {
    @EnvironmentObject private var deps: AppDependencies
    @State private var vm: TextTranslationViewModel?

    var body: some View {
        ZStack {
            GradientBackground()
            content
        }
        .navigationTitle("文字翻譯")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm == nil {
                vm = TextTranslationViewModel(
                    useCase: deps.translateTextUseCase,
                    detector: deps.languageDetector,
                    vocabulary: deps.vocabularyRepository,
                    dictionary: deps.dictionaryService
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            TextTranslationContent(vm: vm)
        } else {
            ProgressView()
        }
    }
}

/// 真正畫面。拿 `@ObservedObject` 就能監聽 VM 更新，
/// 把 VM 生命週期管理留給上層（State）即可。
private struct TextTranslationContent: View {
    @ObservedObject var vm: TextTranslationViewModel

    /// Apple Translation 單次呼叫的安全上限。實測 2000 字元以內非常穩，
    /// 超過會開始出現 modelNotAvailable 或慢到不可接受。
    /// 這個值是「警告/阻擋」用的軟上限，不是硬阻擋（使用者若真的貼超長段落，
    /// 我們顯示紅字提示但仍允許送出，由翻譯服務自行回 error）。
    private static let softCharacterLimit = 2000
    private static let warnThreshold = 1600  // 80% 時變琣願色提醒

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                languageSelector
                inputCard
                outputCard

                if let msg = vm.errorMessage {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(msg)
                                .font(Theme.Font.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("重試") {
                                Task { await vm.translate() }
                            }
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Color.red.opacity(0.08))
                    )
                    .padding(.horizontal, Theme.Spacing.md)
                }

                translateButton
                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
        }
    }

    // MARK: - Subviews

    private var languageSelector: some View {
        HStack(spacing: Theme.Spacing.sm) {
            LanguagePicker(selection: $vm.sourceLanguage, options: Language.allCases)

            Button {
                vm.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)

            LanguagePicker(selection: $vm.targetLanguage, options: vm.availableTargets)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("\(vm.sourceLanguage.flag) \(vm.sourceLanguage.displayName)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Button("自動偵測", action: vm.autoDetectSource)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.accent)
            }

            TextEditor(text: $vm.inputText)
                .font(Theme.Font.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .foregroundStyle(Theme.Colors.textPrimary)

            if !vm.inputText.isEmpty {
                HStack {
                    characterCounter
                    Spacer()
                    Button("清除", action: vm.clear)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .glassCard()
    }

    /// 字元數指示器：綠色 < 80%、琥珀 80%+、紅色 >= 100%
    private var characterCounter: some View {
        let count = vm.inputText.count
        let limit = Self.softCharacterLimit
        let color: Color = {
            if count >= limit { return .red }
            if count >= Self.warnThreshold { return .orange }
            return Theme.Colors.textSecondary
        }()

        return HStack(spacing: 4) {
            Text("\(count) / \(limit)")
                .font(Theme.Font.caption)
                .foregroundStyle(color)
            if count >= limit {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityLabel("已輸入 \(count) 字元，建議上限 \(limit)")
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("\(vm.targetLanguage.flag) \(vm.targetLanguage.displayName)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text("翻譯中…")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 100)
            } else {
                Text(vm.outputText.isEmpty ? "譯文會出現在這裡" : vm.outputText)
                    .font(Theme.Font.body)
                    .foregroundStyle(
                        vm.outputText.isEmpty
                            ? Theme.Colors.textSecondary
                            : Theme.Colors.textPrimary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 100, alignment: .topLeading)
                    .textSelection(.enabled)
            }

            if !vm.outputText.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        Task { await vm.saveToVocabulary() }
                    } label: {
                        Label(vm.isSaved ? "已收藏" : "收藏",
                              systemImage: vm.isSaved ? "star.fill" : "star")
                    }
                    .font(Theme.Font.caption)
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.accent)
                    .disabled(vm.isSaved)

                    Button {
                        UIPasteboard.general.string = vm.outputText
                    } label: {
                        Label("複製", systemImage: "doc.on.doc")
                    }
                    .font(Theme.Font.caption)
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.accent)
                }
            }
        }
        .glassCard()
    }

    private var translateButton: some View {
        Button {
            Task { await vm.translate() }
        } label: {
            HStack {
                if vm.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkles")
                    Text("翻譯").font(Theme.Font.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(Theme.Colors.accent)
            )
            .foregroundStyle(.white)
        }
        .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
        .opacity(
            (vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading) ? 0.6 : 1.0
        )
        .accessibilityLabel(vm.isLoading ? "翻譯進行中" : "翻譯")
        .accessibilityHint("將輸入的文字翻譯為目標語言")
    }
}

// MARK: - LanguagePicker

private struct LanguagePicker: View {
    @Binding var selection: Language
    let options: [Language]

    var body: some View {
        Menu {
            ForEach(options) { lang in
                Button {
                    selection = lang
                } label: {
                    HStack {
                        Text("\(lang.flag) \(lang.displayName)")
                        if selection == lang { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.flag)
                Text(selection.displayName).font(Theme.Font.body)
                Image(systemName: "chevron.down").font(.caption)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.ultraThinMaterial))
        }
    }
}

#Preview {
    NavigationStack {
        TextTranslationView()
    }
    .environmentObject(AppDependencies.makeMock())
}
