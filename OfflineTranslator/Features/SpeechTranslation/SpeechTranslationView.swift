import SwiftUI
import UIKit   // UIPasteboard
import TipKit

struct SpeechTranslationView: View {
    @EnvironmentObject private var deps: AppDependencies
    @State private var vm: SpeechTranslationViewModel?

    var body: some View {
        ZStack {
            GradientBackground()
            if let vm {
                Content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("語音翻譯")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm == nil {
                vm = SpeechTranslationViewModel(useCase: deps.speechTranslateUseCase)
            }
        }
    }

    // MARK: - Content

    private struct Content: View {
        @ObservedObject var vm: SpeechTranslationViewModel

        var body: some View {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    languageBar
                    transcriptCard
                    translationCard
                    errorBanner
                    Spacer(minLength: Theme.Spacing.md)
                    recordButton
                        .padding(.bottom, Theme.Spacing.lg)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }

        // MARK: Subviews

        private var languageBar: some View {
            HStack(spacing: Theme.Spacing.sm) {
                LanguageChip(language: vm.sourceLanguage, caption: "來源")
                Button(action: vm.swapLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(10)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .disabled(vm.isRecording || vm.isBusy)
                LanguageChip(language: vm.targetLanguage, caption: "譯文")
            }
        }

        private var transcriptCard: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("\(vm.sourceLanguage.flag) \(vm.sourceLanguage.displayName) · 辨識結果")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if vm.isRecording {
                        RecordingPulse()
                    }
                }
                Text(currentTranscript.isEmpty ? placeholder : currentTranscript)
                    .font(Theme.Font.body)
                    .foregroundStyle(
                        currentTranscript.isEmpty
                            ? Theme.Colors.textSecondary
                            : Theme.Colors.textPrimary
                    )
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .glassCard()
        }

        private var translationCard: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("\(vm.targetLanguage.flag) \(vm.targetLanguage.displayName) · 譯文")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if vm.phase == .translating {
                        ProgressView().scaleEffect(0.8)
                    } else if !vm.translatedText.isEmpty {
                        Button {
                            Task { await vm.speakTranslation() }
                        } label: {
                            Image(systemName: vm.phase == .speaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .disabled(vm.phase == .speaking)
                    }
                }
                Text(vm.translatedText.isEmpty ? "譯文會出現在這裡" : vm.translatedText)
                    .font(Theme.Font.body)
                    .foregroundStyle(
                        vm.translatedText.isEmpty
                            ? Theme.Colors.textSecondary
                            : Theme.Colors.textPrimary
                    )
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .textSelection(.enabled)

                if !vm.translatedText.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            UIPasteboard.general.string = vm.translatedText
                        } label: {
                            Label("複製", systemImage: "doc.on.doc")
                                .font(Theme.Font.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.Colors.accent)
                    }
                }
            }
            .glassCard()
        }

        @ViewBuilder
        private var errorBanner: some View {
            if let msg = vm.errorMessage {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(msg)
                            .font(Theme.Font.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: Theme.Spacing.md) {
                            if !vm.finalTranscript.trimmingCharacters(in: .whitespaces).isEmpty {
                                Button("重試翻譯") {
                                    Task { await vm.retryTranslation() }
                                }
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.accent)
                            }
                            Button("知道了") {
                                vm.dismissError()
                            }
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Color.red.opacity(0.08))
                )
            }
        }

        private var recordButton: some View {
            VStack(spacing: Theme.Spacing.sm) {
                HoldToSpeakButton(vm: vm)
                Text(buttonHint)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }

        // MARK: Helpers

        private var currentTranscript: String {
            vm.isRecording ? vm.partialTranscript : vm.finalTranscript
        }

        private var placeholder: String {
            vm.isRecording ? "聆聽中…開始說話" : "按住下方麥克風開始錄音"
        }

        private var buttonHint: String {
            switch vm.phase {
            case .idle:        return "按住麥克風開始錄音"
            case .recording:   return "放開結束錄音"
            case .translating: return "翻譯中…"
            case .done:        return "再按住錄下一句"
            case .speaking:    return "朗讀中…"
            }
        }
    }
}

// MARK: - HoldToSpeakButton（長按手勢）

private struct HoldToSpeakButton: View {
    @ObservedObject var vm: SpeechTranslationViewModel
    @GestureState private var isPressing: Bool = false
    /// 記錄 haptic 是否已經在這次按下裡觸發過（避免 onChanged 被重複呼叫時狂震）
    @State private var hasHapticFiredThisPress: Bool = false

    /// v1.1：TipKit 新手引導 — 按住說話
    private let holdTip = HoldToSpeakTip()

    var body: some View {
        let diameter: CGFloat = 112
        let isActive = vm.isRecording

        ZStack {
            Circle()
                .fill(isActive ? Color.red.opacity(0.85) : Theme.Colors.accent)
                .frame(width: diameter, height: diameter)
                .shadow(color: (isActive ? Color.red : Theme.Colors.accent).opacity(0.35),
                        radius: isActive ? 18 : 10, y: 6)

            Image(systemName: isActive ? "mic.fill" : "mic")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
        }
        .scaleEffect(isActive ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        // DragGesture 是最可靠的「按下/放開」偵測方式（LongPressGesture 會要求 minimumDuration）
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressing) { _, state, _ in state = true }
                .onChanged { _ in
                    if !vm.isRecording && !vm.isBusy && !hasHapticFiredThisPress {
                        // 按下瞬間的觸覺回饋（medium → 有點份量，像開始做事的感覺）
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        hasHapticFiredThisPress = true
                        vm.startHold()
                    }
                }
                .onEnded { _ in
                    // 放開的觸覺回饋（light → 輕輕收尾）
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    hasHapticFiredThisPress = false
                    Task {
                        await vm.releaseHold()
                        // v1.1：首次錄完音 → 通知 TipKit 隱藏 hold-to-speak tip
                        HoldToSpeakTip.hasRecordedOnce = true
                    }
                }
        )
        .popoverTip(holdTip)
        .disabled(vm.isBusy)
        .opacity(vm.isBusy ? 0.5 : 1.0)
        .accessibilityLabel(isActive ? "錄音中，放開結束" : "按住開始錄音")
        .accessibilityHint("按住這個按鈕錄下要翻譯的話，放開時會自動翻譯與朗讀")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Supporting views

private struct LanguageChip: View {
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

private struct RecordingPulse: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(animate ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: animate)
            Text("錄音中")
                .font(Theme.Font.caption)
                .foregroundStyle(Color.red)
        }
        .onAppear { animate = true }
    }
}

#Preview {
    NavigationStack { SpeechTranslationView() }
        .environmentObject(AppDependencies.makeMock())
}
