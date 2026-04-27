import SwiftUI
import UIKit

/// 雙向對話模式（v1.2.0）
///
/// 兩位使用者面對面，各自按住自己的麥克風說話：
/// - 系統把該語言辨識成文字
/// - 翻譯成對方語言
/// - 自動朗讀譯文（讓對方聽得到）
/// - 對話歷史以聊天氣泡呈現
struct ConversationView: View {
    @EnvironmentObject private var deps: AppDependencies
    @StateObject private var vmHolder = VMHolder()

    var body: some View {
        ZStack {
            GradientBackground()
            if let vm = vmHolder.vm {
                Content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("雙向對話")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vmHolder.vm == nil {
                vmHolder.vm = ConversationViewModel(useCase: deps.speechTranslateUseCase)
            }
        }
    }

    /// 包一層 holder 是為了延遲 init（避免在 init 時用到 deps）
    @MainActor
    private final class VMHolder: ObservableObject {
        @Published var vm: ConversationViewModel?
    }

    // MARK: - Content

    private struct Content: View {
        @ObservedObject var vm: ConversationViewModel

        var body: some View {
            VStack(spacing: 0) {
                languageBar
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)

                // 對話列表 (chat bubbles)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            if vm.turns.isEmpty && !vm.isRecording {
                                emptyState
                                    .padding(.top, 60)
                            } else {
                                ForEach(vm.turns) { turn in
                                    ConversationBubble(
                                        turn: turn,
                                        sideALanguage: vm.sideALanguage,
                                        onReplay: { Task { await vm.replay(turn: turn) } }
                                    )
                                    .id(turn.id)
                                }
                            }

                            // 即時 partial 顯示（錄音中）
                            if vm.isRecording {
                                LivePartialBubble(
                                    speaker: vm.recordingSide ?? vm.sideALanguage,
                                    text: vm.partialTranscript,
                                    sideALanguage: vm.sideALanguage
                                )
                                .id("partial")
                            }
                        }
                        .padding(Theme.Spacing.lg)
                    }
                    .onChange(of: vm.turns.count) { _, _ in
                        // 新增一筆對話 → 自動捲到最底
                        if let lastId = vm.turns.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                    .onChange(of: vm.partialTranscript) { _, _ in
                        if vm.isRecording {
                            withAnimation { proxy.scrollTo("partial", anchor: .bottom) }
                        }
                    }
                }

                if let msg = vm.errorMessage {
                    errorBanner(msg)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                // 兩顆錄音按鈕（一邊一個）
                HStack(spacing: Theme.Spacing.md) {
                    SideRecordButton(
                        language: vm.sideALanguage,
                        vm: vm,
                        side: .a
                    )
                    SideRecordButton(
                        language: vm.sideBLanguage,
                        vm: vm,
                        side: .b
                    )
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }

        // MARK: - Subviews

        private var languageBar: some View {
            HStack(spacing: Theme.Spacing.sm) {
                LanguageBadge(language: vm.sideALanguage, caption: "你")
                Button(action: vm.swapSides) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(10)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .disabled(vm.isRecording || vm.isBusy)
                LanguageBadge(language: vm.sideBLanguage, caption: "對方")

                if !vm.turns.isEmpty {
                    Button(action: vm.clearAll) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isRecording || vm.isBusy)
                    .accessibilityLabel("清空對話")
                }
            }
        }

        private var emptyState: some View {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.4))
                Text("按住下方按鈕說話")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("放開後系統會自動翻譯給對方聽")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }

        @ViewBuilder
        private func errorBanner(_ msg: String) -> some View {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(msg)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("知道了") { vm.dismissError() }
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Color.red.opacity(0.08))
            )
        }
    }
}

// MARK: - Chat Bubble

/// 「我方」(side A) 顯示在右、「對方」(side B) 顯示在左，模仿訊息 App 慣例。
private struct ConversationBubble: View {
    let turn: ConversationTurn
    let sideALanguage: Language
    let onReplay: () -> Void

    private var isSelf: Bool { turn.speaker == sideALanguage }

    var body: some View {
        HStack(alignment: .top) {
            if isSelf { Spacer(minLength: 40) }
            VStack(alignment: isSelf ? .trailing : .leading, spacing: 6) {
                // 原文
                Text(turn.originalText)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(isSelf ? .trailing : .leading)

                Divider().opacity(0.3)

                // 譯文
                HStack(alignment: .top, spacing: 6) {
                    if !isSelf {
                        Button(action: onReplay) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("再聽一次")
                    }
                    Text(turn.translatedText)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Colors.accent)
                        .multilineTextAlignment(isSelf ? .trailing : .leading)
                    if isSelf {
                        Button(action: onReplay) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("再聽一次")
                    }
                }

                // 來源 / 對方 標籤
                Text("\(turn.speaker.flag) \(turn.speaker.displayName) → \(turn.listener.flag) \(turn.listener.displayName)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: isSelf ? .trailing : .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(.ultraThinMaterial)
            )
            if !isSelf { Spacer(minLength: 40) }
        }
    }
}

/// 即時 partial 辨識氣泡（錄音中閃爍顯示）
private struct LivePartialBubble: View {
    let speaker: Language
    let text: String
    let sideALanguage: Language

    private var isSelf: Bool { speaker == sideALanguage }

    var body: some View {
        HStack {
            if isSelf { Spacer(minLength: 40) }
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(text.isEmpty ? "聆聽中…" : text)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .italic()
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Color.red.opacity(0.1))
            )
            if !isSelf { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Side Record Button

private enum ConversationSide { case a, b }

private struct SideRecordButton: View {
    let language: Language
    @ObservedObject var vm: ConversationViewModel
    let side: ConversationSide

    @GestureState private var isPressing: Bool = false
    @State private var hapticFired: Bool = false

    /// 此按鈕對應的語言是否正在錄音
    private var isThisSideRecording: Bool {
        vm.recordingSide == language
    }

    /// 別人在錄音時，這顆要 disable
    private var isOtherSideBusy: Bool {
        vm.isRecording && !isThisSideRecording || vm.isBusy
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isThisSideRecording ? Color.red.opacity(0.85) : Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .shadow(color: (isThisSideRecording ? Color.red : Theme.Colors.accent).opacity(0.35),
                            radius: isThisSideRecording ? 16 : 8, y: 4)

                VStack(spacing: 4) {
                    Image(systemName: isThisSideRecording ? "mic.fill" : "mic")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(language.flag) \(language.displayName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(isThisSideRecording ? 1.04 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isThisSideRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
                    .onChanged { _ in
                        if !isOtherSideBusy && !isThisSideRecording && !hapticFired {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            hapticFired = true
                            vm.startHold(speaker: language)
                        }
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        hapticFired = false
                        if isThisSideRecording {
                            Task { await vm.releaseHold() }
                        }
                    }
            )
            .opacity(isOtherSideBusy ? 0.4 : 1.0)
            .accessibilityLabel(isThisSideRecording ? "\(language.displayName) 錄音中，放開結束" : "\(language.displayName) 按住說話")

            Text(isThisSideRecording ? "放開結束" : "按住說話")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

// MARK: - LanguageBadge

private struct LanguageBadge: View {
    let language: Language
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("\(language.flag) \(language.displayName)")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Capsule().fill(.ultraThinMaterial))
    }
}

#Preview {
    NavigationStack {
        ConversationView()
    }
    .environmentObject(AppDependencies.makeMock())
}
