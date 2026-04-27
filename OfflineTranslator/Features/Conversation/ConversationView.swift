import SwiftUI
import UIKit

/// 雙向對話模式（v1.2.1：上下分割，上方旋轉 180°）
///
/// 使用情境：手機平放在兩人之間。
/// - 上半部：對方視角，**整個畫面旋轉 180°**，讓對方坐在對面也能正面閱讀。
/// - 下半部：我自己看，文字方向正常。
/// - 兩人各自有自己「順手位置」的麥克風（你按下方、對方按上方那顆，
///   旋轉後對方看到的是「正常方向」的麥克風按鈕在他自己的下方）。
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
                // ─────── 上半部：對方視角（整個旋轉 180°）───────
                topHalf
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .rotationEffect(.degrees(180))

                // ─────── 中間分隔線（含 swap 按鈕）───────
                middleDivider

                // ─────── 下半部：我自己（正常方向）───────
                bottomHalf
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        // MARK: 上半（對方視角，會被 rotation 180°）

        private var topHalf: some View {
            VStack(spacing: 0) {
                // 對方的麥克風（旋轉後會出現在「對方那一側的下方」）
                SideRecordButton(
                    language: vm.sideBLanguage,
                    vm: vm
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)

                // 對方的對話顯示
                ChatScroll(
                    vm: vm,
                    selfLanguage: vm.sideBLanguage,
                    scrollAnchorId: "topAnchor"
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)

                if let msg = vm.errorMessage {
                    errorBanner(msg)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.sm)
                }
            }
        }

        // MARK: 下半（我自己）

        private var bottomHalf: some View {
            VStack(spacing: 0) {
                // 我這邊的對話顯示
                ChatScroll(
                    vm: vm,
                    selfLanguage: vm.sideALanguage,
                    scrollAnchorId: "bottomAnchor"
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)

                if let msg = vm.errorMessage {
                    errorBanner(msg)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.sm)
                }

                // 我的麥克風
                SideRecordButton(
                    language: vm.sideALanguage,
                    vm: vm
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            }
        }

        // MARK: 中間分隔線

        private var middleDivider: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Rectangle()
                    .fill(Theme.Colors.textSecondary.opacity(0.25))
                    .frame(height: 1)

                Button(action: vm.swapSides) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(8)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .disabled(vm.isRecording || vm.isBusy)
                .accessibilityLabel("交換上下語言")

                if !vm.turns.isEmpty {
                    Button(action: vm.clearAll) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(8)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isRecording || vm.isBusy)
                    .accessibilityLabel("清空對話")
                }

                Rectangle()
                    .fill(Theme.Colors.textSecondary.opacity(0.25))
                    .frame(height: 1)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: 36)
        }

        // MARK: 錯誤條

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

// MARK: - ChatScroll

/// 顯示對話歷史。`selfLanguage` 決定在這個視角下，誰算「自己」（右靠齊）、
/// 誰算「對方」（左靠齊）。
private struct ChatScroll: View {
    @ObservedObject var vm: ConversationViewModel
    let selfLanguage: Language
    let scrollAnchorId: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    if vm.turns.isEmpty && !vm.isRecording {
                        emptyState
                            .padding(.top, 30)
                    } else {
                        ForEach(vm.turns) { turn in
                            ConversationBubble(
                                turn: turn,
                                selfLanguage: selfLanguage,
                                onReplay: { Task { await vm.replay(turn: turn) } },
                                onRetry: { Task { await vm.retryTurn(turn) } }
                            )
                            .id("\(scrollAnchorId)-\(turn.id)")
                        }
                    }

                    if vm.isRecording {
                        LivePartialBubble(
                            speaker: vm.recordingSide ?? selfLanguage,
                            text: vm.partialTranscript,
                            selfLanguage: selfLanguage
                        )
                        .id("\(scrollAnchorId)-partial")
                    }

                    // bottom anchor 用來 auto-scroll
                    Color.clear.frame(height: 1).id("\(scrollAnchorId)-bottom")
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
            .onChange(of: vm.turns.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("\(scrollAnchorId)-bottom", anchor: .bottom)
                }
            }
            .onChange(of: vm.partialTranscript) { _, _ in
                if vm.isRecording {
                    withAnimation {
                        proxy.scrollTo("\(scrollAnchorId)-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.Colors.accent.opacity(0.4))
            Text("按住下方按鈕說話")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("放開後系統會自動翻譯給對方聽")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ConversationBubble

/// 對話氣泡：v1.2.1 修正
/// 規則：翻譯成功 / 失敗 / 進行中，都**永遠保留雙邊文字**（原文 + 譯文/狀態）
/// - 自己說的：靠右；原文較大、譯文較小
/// - 對方說的：靠左；譯文較大（我看得懂的語言）、原文較小
/// - 翻譯失敗：顯示重試按鈕
/// - 翻譯進行中：顯示「翻譯中…」灰字
private struct ConversationBubble: View {
    let turn: ConversationTurn
    let selfLanguage: Language
    let onReplay: () -> Void
    let onRetry: () -> Void

    private var isSelf: Bool { turn.speaker == selfLanguage }

    var body: some View {
        HStack(alignment: .top) {
            if isSelf { Spacer(minLength: 30) }
            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                if isSelf {
                    // 自己說的話：原文（自己的語言）大字、譯文小字
                    Text(turn.originalText)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.trailing)

                    translationPart(alignmentTrailing: true)
                } else {
                    // 對方說的話：譯文（自己的語言）大字、原文小字
                    translationPart(alignmentTrailing: false)

                    Text(turn.originalText)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(.ultraThinMaterial)
            )
            if !isSelf { Spacer(minLength: 30) }
        }
    }

    /// 譯文 / 錯誤 / 進行中 — 三態
    @ViewBuilder
    private func translationPart(alignmentTrailing: Bool) -> some View {
        if let err = turn.translationError {
            // 翻譯失敗：顯示錯誤 + 重試
            HStack(spacing: 6) {
                if !alignmentTrailing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: alignmentTrailing ? .trailing : .leading, spacing: 2) {
                    Text(err)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(alignmentTrailing ? .trailing : .leading)
                    Button("重試", action: onRetry)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
                if alignmentTrailing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }
        } else if turn.translatedText.isEmpty {
            // 翻譯進行中（已加入歷史，等待結果）
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("翻譯中…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } else {
            // 翻譯成功：譯文 + 喇叭
            HStack(alignment: .center, spacing: 6) {
                if !alignmentTrailing {
                    Button(action: onReplay) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("再聽一次")
                }
                Text(turn.translatedText)
                    .font(alignmentTrailing ? Theme.Font.caption : Theme.Font.body)
                    .foregroundStyle(alignmentTrailing ? Theme.Colors.accent : Theme.Colors.textPrimary)
                    .multilineTextAlignment(alignmentTrailing ? .trailing : .leading)
                if alignmentTrailing {
                    Button(action: onReplay) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("再聽一次")
                }
            }
        }
    }
}

// MARK: - LivePartialBubble

private struct LivePartialBubble: View {
    let speaker: Language
    let text: String
    let selfLanguage: Language

    private var isSelf: Bool { speaker == selfLanguage }

    var body: some View {
        HStack {
            if isSelf { Spacer(minLength: 30) }
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
            if !isSelf { Spacer(minLength: 30) }
        }
    }
}

// MARK: - SideRecordButton

private struct SideRecordButton: View {
    let language: Language
    @ObservedObject var vm: ConversationViewModel

    @GestureState private var isPressing: Bool = false
    @State private var hapticFired: Bool = false

    private var isThisSideRecording: Bool { vm.recordingSide == language }
    private var isOtherSideBusy: Bool {
        (vm.isRecording && !isThisSideRecording) || vm.isBusy
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isThisSideRecording ? Color.red.opacity(0.85) : Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .shadow(color: (isThisSideRecording ? Color.red : Theme.Colors.accent).opacity(0.35),
                            radius: isThisSideRecording ? 14 : 6, y: 4)

                HStack(spacing: 12) {
                    Image(systemName: isThisSideRecording ? "mic.fill" : "mic")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(language.flag) \(language.displayName)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(isThisSideRecording ? "放開結束" : "按住說話")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
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
        }
    }
}

#Preview {
    NavigationStack {
        ConversationView()
    }
    .environmentObject(AppDependencies.makeMock())
}
