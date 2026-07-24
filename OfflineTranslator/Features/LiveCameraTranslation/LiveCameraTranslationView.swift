import SwiftUI
import AVFoundation

/// v1.4.0：即時鏡頭翻譯主畫面。
///
/// 三層結構（沿用 v1.2.0 設計文件）：
///   Layer 1  相機即時畫面
///   Layer 2  譯文疊層（每個 region 一個 TextOverlayView）
///   Layer 3  控制列（語言 picker / 交換 / 暫停）
///   Layer 4  狀態遮罩（載入 / 無權限 / 失敗）
///   Layer 5  關閉鍵 —— 永遠在最上層，任何狀態都點得到
///
/// **重要**：實際內容放在 `Content` struct 並用 `@ObservedObject` 訂閱 VM，
/// 跟 ConversationView / SpeechTranslationView 同一個 pattern。
/// v1.4.0 hotfix3 之前這裡把 vm 當普通函式參數傳，View 因此完全不觀察 VM ——
/// phase / regions 再怎麼變畫面都不重繪（build #53、#54 的真正病根）。
struct LiveCameraTranslationView: View {
    @EnvironmentObject private var deps: AppDependencies
    @StateObject private var holder = VMHolder()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let vm = holder.vm {
                Content(vm: vm)
            } else {
                ProgressView().tint(.white)
            }
        }
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        // 同步建立 VM，啟動流程由 VM 自己的 Task 驅動（不靠 `.task { }`，那個會被取消）
        .onAppear {
            if holder.vm == nil {
                holder.vm = LiveCameraTranslationViewModel(service: deps.liveCameraService)
            }
            holder.vm?.begin()
        }
        .onDisappear { holder.vm?.onDisappear() }
    }

    /// 延遲建立 VM（需要 deps）
    @MainActor
    private final class VMHolder: ObservableObject {
        @Published var vm: LiveCameraTranslationViewModel?
    }

    // MARK: - Content

    private struct Content: View {
        @ObservedObject var vm: LiveCameraTranslationViewModel
        @Environment(\.dismiss) private var dismiss

        /// 直向 720x1280 的長寬比
        private let cameraAspect: CGFloat = 720.0 / 1280.0

        var body: some View {
            ZStack {
                // ── Layer 1：相機畫面（凍結時換成拍下來的靜止畫面）
                if let still = vm.still {
                    Image(uiImage: still.image)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    CameraPreviewLayer(session: vm.captureSession)
                        .ignoresSafeArea()
                }

                // ── Layer 2：譯文疊層
                // 凍結畫面沿用相同的方向與 720p 長寬比，所以座標換算完全共用。
                GeometryReader { geo in
                    ForEach(vm.still?.regions ?? vm.regions) { region in
                        TextOverlayView(
                            region: region,
                            viewSize: geo.size,
                            cameraAspect: cameraAspect
                        )
                    }
                    .animation(.easeOut(duration: 0.18), value: vm.regions)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // ── Layer 3：控制列（running 才顯示，避免載入時誤觸）
                if vm.phase == .running {
                    VStack(spacing: 0) {
                        Spacer()
                        if vm.still == nil { statusBanner }
                        controlsBar
                    }
                }

                // ── Layer 4：狀態遮罩
                stateOverlay

                // ── Layer 5：關閉鍵，永遠可按
                VStack {
                    topBar
                    Spacer()
                }

                // ── Layer 6：快門處理中
                if vm.isCapturing {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: Theme.Spacing.sm) {
                            ProgressView().tint(.white)
                            Text("live.status.capturing")
                                .font(Theme.Font.caption)
                                .foregroundStyle(.white)
                        }
                        .padding(Theme.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                .fill(.black.opacity(0.7))
                        )
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.still == nil)
        }

        // MARK: Top bar

        private var topBar: some View {
            HStack {
                Spacer()
                Button {
                    vm.onDisappear()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .accessibilityLabel(Text("live.action.close"))
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }

        // MARK: Status banner

        @ViewBuilder
        private var statusBanner: some View {
            VStack(spacing: 6) {
                if vm.isThermallyThrottled {
                    banner(icon: "thermometer.high", key: "live.hint.thermal", tint: .orange)
                }
                if vm.showsAimHint {
                    banner(icon: "viewfinder", key: "live.hint.aim", tint: .white)
                }
                if vm.hasTextButNoTranslation {
                    banner(icon: "arrow.down.circle", key: "live.hint.pack_not_ready", tint: .yellow)
                }
                if vm.isPaused {
                    banner(icon: "pause.fill", key: "live.hint.paused", tint: .white)
                }
            }
            .padding(.bottom, Theme.Spacing.sm)
        }

        private func banner(icon: String, key: LocalizedStringKey, tint: Color) -> some View {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(key)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.6)))
        }

        // MARK: Controls

        /// v1.4.0 hotfix6：底部控制區。
        /// 即時模式 = 語言列 + 快門；單張模式 = 只留「返回即時預覽」。
        @ViewBuilder
        private var controlsBar: some View {
            if vm.still == nil {
                VStack(spacing: Theme.Spacing.md) {
                    languageRow
                    shutterButton
                }
                .padding(.bottom, Theme.Spacing.lg)
            } else {
                Button { vm.resumeLive() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("live.action.back_to_live")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(.white))
                }
                .padding(.bottom, Theme.Spacing.lg)
            }
        }

        private var languageRow: some View {
            HStack(spacing: Theme.Spacing.sm) {
                ConversationLanguageMenu(
                    current: vm.sourceLanguage,
                    options: Language.allCases,
                    excluded: vm.targetLanguage,
                    disabled: false,
                    onSelect: { vm.setSource($0) }
                )

                Button { vm.swapLanguages() } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Circle().fill(.white.opacity(0.18)))
                }
                .accessibilityLabel(Text("交換來源與譯文"))

                ConversationLanguageMenu(
                    current: vm.targetLanguage,
                    options: vm.availableTargets,
                    excluded: vm.sourceLanguage,
                    disabled: false,
                    onSelect: { vm.setTarget($0) }
                )
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(.black.opacity(0.5))
            )
            .padding(.horizontal, Theme.Spacing.md)
        }

        /// 相機式快門鍵：外圈白環 + 內圈實心，跟系統相機一致的視覺語彙。
        private var shutterButton: some View {
            Button { vm.capture() } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 70, height: 70)
                    Circle()
                        .fill(.white)
                        .frame(width: 56, height: 56)
                }
            }
            .disabled(vm.isCapturing)
            .opacity(vm.isCapturing ? 0.5 : 1)
            .accessibilityLabel(Text("live.action.shutter"))
        }

        // MARK: Phase overlays

        @ViewBuilder
        private var stateOverlay: some View {
            switch vm.phase {
            case .requestingPermission:
                loadingCard(textKey: "live.status.requesting_permission")

            case .starting:
                loadingCard(textKey: "live.status.starting")

            case .noPermission:
                centeredCard {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                        Text("live.permission.title")
                            .font(Theme.Font.headline)
                            .foregroundStyle(.white)
                        Text("live.permission.body")
                            .font(Theme.Font.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                        Button("live.permission.open_settings") { vm.openSystemSettings() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Colors.accent)
                    }
                }

            case .failed(let message):
                centeredCard {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(Theme.Font.caption)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        HStack(spacing: Theme.Spacing.md) {
                            Button("live.action.retry") { vm.retry() }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.Colors.accent)
                            Button("live.action.cancel") {
                                vm.onDisappear()
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                    }
                }

            case .idle, .running:
                EmptyView()
            }
        }

        /// 載入中卡片。一定要帶「取消」，任何階段都不能把使用者關在裡面。
        private func loadingCard(textKey: LocalizedStringKey) -> some View {
            centeredCard {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView().tint(.white)
                    Text(textKey)
                        .font(Theme.Font.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("live.action.cancel") {
                        vm.onDisappear()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        }

        private func centeredCard<C: View>(@ViewBuilder content: () -> C) -> some View {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                content()
                    .padding(Theme.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .fill(.black.opacity(0.75))
                    )
                    .padding(Theme.Spacing.xl)
            }
        }
    }
}

#Preview {
    LiveCameraTranslationView()
        .environmentObject(AppDependencies.makeMock())
}
