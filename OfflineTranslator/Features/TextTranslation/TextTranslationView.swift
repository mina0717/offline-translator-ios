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
                    detector: deps.languageDetector
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

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                languageSelector
                inputCard
                outputCard

                if let msg = vm.errorMessage {
                    Text(msg)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Spacer()
                    Button("清除", action: vm.clear)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .glassCard()
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
