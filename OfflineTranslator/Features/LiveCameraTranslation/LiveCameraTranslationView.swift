import SwiftUI
import AVFoundation

/// v1.4.0：即時鏡頭翻譯主畫面。
///
/// 三層結構（沿用 v1.2.0 設計文件）：
///   Layer 1  相機即時畫面
///   Layer 2  譯文疊層（每個 region 一個 TextOverlayView）
///   Layer 3  控制列（語言 picker / 交換 / 暫停 / 關閉）
struct LiveCameraTranslationView: View {
    @EnvironmentObject private var deps: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @StateObject private var holder = VMHolder()

    /// 直向 720x1280 的長寬比
    private let cameraAspect: CGFloat = 720.0 / 1280.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let vm = holder.vm {
                content(vm: vm)
            } else {
                ProgressView().tint(.white)
            }
        }
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        .task {
            if holder.vm == nil {
                holder.vm = LiveCameraTranslationViewModel(
                    service: deps.liveCameraService
                )
            }
            await holder.vm?.onAppear()
        }
        .onDisappear { holder.vm?.onDisappear() }
    }

    @MainActor
    private func content(vm: LiveCameraTranslationViewModel) -> some View {
        ZStack {
            // ── Layer 1：相機畫面
            CameraPreviewLayer(session: vm.captureSession)
                .ignoresSafeArea()

            // ── Layer 2：譯文疊層
            GeometryReader { geo in
                ForEach(vm.regions) { region in
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
                    statusBanner(vm: vm)
                    controlsBar(vm: vm)
                }
            }

            // ── Layer 4：狀態遮罩（載入 / 無權限 / 失敗）
            stateOverlay(vm: vm)

            // ── Layer 5：關閉鍵。v1.4.0 hotfix：**永遠**在最上層。
            // 之前 stateOverlay 蓋在 topBar 上面，一旦卡在 .starting 就完全點不到，
            // 加上隱藏了返回鍵，使用者只能強制關閉 App。
            VStack {
                topBar(vm: vm)
                Spacer()
            }
        }
    }

    // MARK: - Top bar

    private func topBar(vm: LiveCameraTranslationViewModel) -> some View {
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

    // MARK: - Status banner

    @ViewBuilder
    private func statusBanner(vm: LiveCameraTranslationViewModel) -> some View {
        VStack(spacing: 6) {
            if vm.isThermallyThrottled {
                banner(icon: "thermometer.high", key: "live.hint.thermal", tint: .orange)
            }
            if vm.showsAimHint {
                banner(icon: "viewfinder", key: "live.hint.aim", tint: .white)
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

    // MARK: - Controls

    private func controlsBar(vm: LiveCameraTranslationViewModel) -> some View {
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

            Button { vm.togglePause() } label: {
                Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(Circle().fill(.white.opacity(0.18)))
            }
            .accessibilityLabel(Text(vm.isPaused
                                     ? LocalizedStringKey("live.action.resume")
                                     : LocalizedStringKey("live.action.pause")))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(.black.opacity(0.5))
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
    }

    // MARK: - Phase overlays

    @ViewBuilder
    private func stateOverlay(vm: LiveCameraTranslationViewModel) -> some View {
        switch vm.phase {
        case .requestingPermission, .starting:
            centeredCard {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView().tint(.white)
                    Text("live.status.starting")
                        .font(Theme.Font.body)
                        .foregroundStyle(.white)
                    // hotfix：載入中也一定要有退路
                    Button("live.action.cancel") {
                        vm.onDisappear()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }

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
                        Button("live.action.retry") { Task { await vm.retry() } }
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

    private func centeredCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

    /// 延遲建立 VM（需要 deps）
    @MainActor
    private final class VMHolder: ObservableObject {
        @Published var vm: LiveCameraTranslationViewModel?
    }
}

#Preview {
    LiveCameraTranslationView()
        .environmentObject(AppDependencies.makeMock())
}
