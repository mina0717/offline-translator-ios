import SwiftUI

/// v1.5.0：**主畫面的免持聆聽模式**。
///
/// 設計取向與雙向對話完全不同：
/// - 雙向對話：畫面上下對切，兩人面對面。
/// - 這一頁：**整頁單向**。使用者用耳朵聽對方講、用眼睛看螢幕上的譯文。
///   場景是聽演講、聽導覽、聽對方講一長段。
///
/// 所以排版重點是「**譯文要大、要好讀、自動捲到最新**」，
/// 原文縮小放在譯文下方當參考。
struct HandsFreeListeningView: View {
    @EnvironmentObject private var deps: AppDependencies
    @StateObject private var holder = VMHolder()

    var body: some View {
        ZStack {
            GradientBackground()
            if let vm = holder.vm {
                Content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("免持聆聽")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if holder.vm == nil {
                holder.vm = HandsFreeListeningViewModel(
                    service: deps.handsFreeASRService,
                    useCase: deps.speechTranslateUseCase
                )
            }
        }
        .onDisappear { holder.vm?.stop() }
    }

    @MainActor
    private final class VMHolder: ObservableObject {
        @Published var vm: HandsFreeListeningViewModel?
    }

    // MARK: - Content

    private struct Content: View {
        @ObservedObject var vm: HandsFreeListeningViewModel

        var body: some View {
            VStack(spacing: 0) {
                languageBar
                if let msg = vm.errorMessage { errorBanner(msg) }
                transcriptArea
                bottomBar
            }
        }

        // MARK: 語言列

        private var languageBar: some View {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("對方說")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    LanguagePickerChip(
                        current: vm.sourceLanguage,
                        options: Language.allCases,
                        excluded: vm.targetLanguage,
                        caption: "",
                        disabled: false,
                        onSelect: { vm.sourceLanguage = $0 }
                    )
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("我讀")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    LanguagePickerChip(
                        current: vm.targetLanguage,
                        options: vm.availableTargets,
                        excluded: vm.sourceLanguage,
                        caption: "",
                        disabled: false,
                        onSelect: { vm.targetLanguage = $0 }
                    )
                }

                Spacer(minLength: 0)

                if !vm.lines.isEmpty && !vm.isListening {
                    Button(action: vm.clearAll) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(8)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空")
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }

        // MARK: 譯文區

        private var transcriptArea: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if vm.isEmpty {
                            emptyState
                        }

                        ForEach(vm.lines) { line in
                            lineCard(line)
                                .id(line.id)
                        }

                        // 辨識中的即時文字
                        if !vm.partialText.isEmpty {
                            partialCard
                                .id(Self.partialAnchor)
                        }

                        Color.clear.frame(height: 8).id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)
                }
                // 自動捲到最新 —— 免持模式使用者的手可能不在螢幕上
                .onChange(of: vm.lines.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: vm.partialText) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }

        private static let bottomAnchor = "listening-bottom"
        private static let partialAnchor = "listening-partial"

        /// 一句：**譯文大、原文小**。使用者主要是在讀譯文。
        private func lineCard(_ line: ListeningLine) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                if line.hasTranslation {
                    Text(line.translatedText)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else if line.errorMessage != nil {
                    HStack(spacing: 6) {
                        Text(line.errorMessage ?? "")
                            .font(Theme.Font.caption)
                            .foregroundStyle(.orange)
                        Button("重試") { vm.retry(line) }
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("翻譯中…")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Text(line.originalText)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }

        private var partialCard: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(vm.partialText)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.accent.opacity(0.08))
            )
        }

        private var emptyState: some View {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "ear.and.waveform")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
                Text("按下方按鈕開始聆聽")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("手不用一直按著。對方講完一句，譯文就會自動出現在這裡。")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .padding(.horizontal, Theme.Spacing.lg)
        }

        // MARK: 底部按鈕

        private var bottomBar: some View {
            VStack(spacing: Theme.Spacing.sm) {
                if vm.isListening {
                    HStack(spacing: 8) {
                        Image(systemName: vm.isHearingSpeech ? "waveform.circle.fill" : "waveform.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(vm.isHearingSpeech ? Theme.Colors.accent : Theme.Colors.textSecondary)
                            .scaleEffect(vm.isHearingSpeech ? 1.15 : 1.0)
                            .animation(.easeOut(duration: 0.18), value: vm.isHearingSpeech)
                        Text(vm.isHearingSpeech ? "聽到了…" : "聆聽中，請對方開始說話")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Button {
                    vm.toggleListening()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: vm.isListening ? "stop.fill" : "ear.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text(vm.isListening ? "停止聆聽" : "開始聆聽")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(vm.isListening ? Color.red.opacity(0.9) : Theme.Colors.accent)
                            .shadow(
                                color: (vm.isListening ? Color.red : Theme.Colors.accent).opacity(0.35),
                                radius: vm.isListening ? 14 : 8, y: 4
                            )
                    )
                }
                .buttonStyle(.plain)
                .scaleEffect(vm.isListening ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.isListening)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
        }

        // MARK: 錯誤條

        private func errorBanner(_ msg: String) -> some View {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    vm.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Color.orange.opacity(0.12))
            )
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xs)
        }
    }
}

#Preview {
    NavigationStack { HandsFreeListeningView() }
        .environmentObject(AppDependencies.makeMock())
}
