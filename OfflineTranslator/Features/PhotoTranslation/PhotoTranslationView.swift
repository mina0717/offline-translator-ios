import SwiftUI
import UIKit      // UIImage, UIImagePickerController, UIPasteboard
import PhotosUI
import TipKit

struct PhotoTranslationView: View {
    @EnvironmentObject private var deps: AppDependencies
    @State private var vm: PhotoTranslationViewModel?

    var body: some View {
        ZStack {
            GradientBackground()
            if let vm {
                Content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("拍照翻譯")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm == nil {
                vm = PhotoTranslationViewModel(useCase: deps.photoTranslateUseCase)
            }
        }
    }

    // MARK: - Content

    private struct Content: View {
        @ObservedObject var vm: PhotoTranslationViewModel
        @State private var photoPickerItem: PhotosPickerItem?
        @State private var showCamera: Bool = false
        /// v1.2.5：tap 圖片 → 全螢幕可縮放檢視
        @State private var showFullscreen: Bool = false

        /// v1.1：TipKit 新手引導
        private let cameraTip = CameraTip()
        private let swapTip = LanguageSwitchTip()

        var body: some View {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    languageBar
                    detectionBanner    // v1.2.5：自動偵測語言提示
                    imageCard          // v1.2.5：放大圖片區 + tap 全螢幕
                    actionButtons
                    errorBanner
                    if vm.hasResults && vm.phase == .done {
                        displayModePicker
                        if vm.displayMode == .list {
                            regionListCard
                        }
                        // v1.2.5：移除複製按鈕，列表模式下使用者可以選取單塊文字複製
                    } else if vm.phase == .translating {
                        VStack(spacing: Theme.Spacing.sm) {
                            ProgressView()
                            Text("辨識完成，逐塊翻譯中…")
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.md)
                        .glassCard()
                    }
                    Spacer(minLength: Theme.Spacing.xl)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
            .onChange(of: photoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await vm.process(image: image)
                    }
                    photoPickerItem = nil
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image {
                        Task { await vm.process(image: image) }
                    }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showFullscreen) {
                if let image = vm.pickedImage {
                    FullscreenZoomableImage(
                        image: image,
                        regions: vm.regions,
                        showOverlay: vm.displayMode == .overlay && vm.phase == .done,
                        onClose: { showFullscreen = false }
                    )
                }
            }
        }

        // MARK: Subviews

        private var languageBar: some View {
            HStack(spacing: Theme.Spacing.sm) {
                LanguageChip(language: vm.sourceLanguage, caption: "來源")
                Button {
                    vm.swapLanguages()
                    LanguageSwitchTip.hasSwappedOnce = true
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(10)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .disabled(vm.isProcessing)
                .popoverTip(swapTip)
                LanguageChip(language: vm.targetLanguage, caption: "譯文")
            }
        }

        @ViewBuilder
        private var imageCard: some View {
            if let image = vm.pickedImage {
                // v1.2.7：圖片區進一步放大（min 400 / max 700），按鈕變緊湊省空間給圖
                ImageWithOverlay(
                    image: image,
                    regions: vm.regions,
                    showOverlay: vm.displayMode == .overlay && vm.phase == .done
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 400, maxHeight: 700)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .stroke(.white.opacity(0.3), lineWidth: 0.5)
                )
                .overlay(alignment: .topTrailing) {
                    if vm.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text(vm.phase == .recognizing ? "辨識中…" : "翻譯中…")
                                .font(Theme.Font.caption)
                                .foregroundStyle(.white)
                        }
                        .padding(8)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // v1.2.5：放大鏡按鈕 → 全螢幕可縮放
                    if vm.phase == .done {
                        Button {
                            showFullscreen = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .padding(10)
                        .accessibilityLabel("放大檢視")
                    }
                }
                .onTapGesture(count: 2) {
                    if vm.phase == .done { showFullscreen = true }
                }
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Theme.Colors.accent)
                    Text("拍照或從相簿選一張有文字的圖")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                    Text("譯文會直接疊在原圖上（Google Lens 風格）")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .glassCard()
            }
        }

        /// v1.2.7：按鈕縮小，留空間給圖片
        private var actionButtons: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    showCamera = true
                    CameraTip.hasUsedCameraOnce = true
                } label: {
                    Label("相機", systemImage: "camera")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .controlSize(.small)
                .disabled(vm.isProcessing)
                .popoverTip(cameraTip)

                PhotosPicker(
                    selection: $photoPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("相簿", systemImage: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
                .controlSize(.small)
                .disabled(vm.isProcessing)

                if vm.pickedImage != nil {
                    Button {
                        vm.clear()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .disabled(vm.isProcessing)
                }
            }
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
                        if vm.pickedImage != nil {
                            Button("重試") {
                                Task { await vm.retry() }
                            }
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.accent)
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

        /// v1.2.4：顯示模式切換器
        private var displayModePicker: some View {
            Picker("顯示", selection: $vm.displayMode) {
                ForEach(PhotoTranslationViewModel.DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
        }

        /// 列表模式：每塊原文 + 譯文並列
        private var regionListCard: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(vm.regions) { region in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(region.text)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        if let translated = region.translatedText, !translated.isEmpty {
                            Text(translated)
                                .font(Theme.Font.translationEmphasized)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        } else {
                            Text("（此塊未翻譯）")
                                .font(Theme.Font.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(.ultraThinMaterial)
                    )
                }
            }
            .glassCard()
        }

        /// v1.2.5：自動偵測語言提示（藍色橫條）
        @ViewBuilder
        private var detectionBanner: some View {
            if let hint = vm.detectionHint {
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    Image(systemName: "wand.and.sparkles")
                        .foregroundStyle(Theme.Colors.accent)
                    Text(hint)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Colors.accent.opacity(0.10))
                )
            }
        }
    }
}

// MARK: - ImageWithOverlay (Google Lens 風格疊圖)

/// v1.2.4：把 OCR regions 的譯文疊在原圖上對應 bounding box 位置。
/// v1.2.7：chip 嚴格限制在 bbox 範圍內不互相重疊；tap chip 跳出大尺寸 popover 顯示完整譯文 + 原文。
private struct ImageWithOverlay: View {
    let image: UIImage
    let regions: [OCRRegion]
    let showOverlay: Bool

    @State private var selectedId: UUID?

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let imgSize = image.size
            let scale = min(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
            let drawnSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let offsetX = (viewSize.width - drawnSize.width) / 2
            let offsetY = (viewSize.height - drawnSize.height) / 2

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: viewSize.width, height: viewSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedId = nil }

                if showOverlay {
                    // Layer 1：每塊 chip 嚴格限制在原 bbox 內，不互相重疊
                    ForEach(regions) { region in
                        if let translated = region.translatedText, !translated.isEmpty,
                           selectedId != region.id {
                            chipView(
                                region: region,
                                translated: translated,
                                offsetX: offsetX, offsetY: offsetY,
                                drawnSize: drawnSize
                            )
                        }
                    }

                    // Layer 2：被選中的那一塊跳出 popover（zIndex 最高，覆蓋鄰近 chip）
                    if let id = selectedId,
                       let r = regions.first(where: { $0.id == id }),
                       let t = r.translatedText {
                        popoverView(
                            region: r, translated: t,
                            viewSize: viewSize,
                            offsetX: offsetX, offsetY: offsetY,
                            drawnSize: drawnSize
                        )
                    }
                }
            }
        }
        .aspectRatio(image.size, contentMode: .fit)
    }

    /// v1.2.8：chip 跟著文字長度延伸（不再嚴格 bbox），畫面恢復可讀；
    /// 重疊問題改用「tap 任一塊跳出 popover 蓋過鄰居」解決，不靠 chip 本身擠滿小字。
    @ViewBuilder
    private func chipView(
        region: OCRRegion, translated: String,
        offsetX: CGFloat, offsetY: CGFloat,
        drawnSize: CGSize
    ) -> some View {
        let bx = offsetX + region.boundingBox.minX * drawnSize.width
        let by = offsetY + region.boundingBox.minY * drawnSize.height
        let bw = region.boundingBox.width * drawnSize.width
        let bh = region.boundingBox.height * drawnSize.height

        Text(translated)
            // v1.2.9：字級縮小（11pt 起跳，原文高度 0.55 倍），減少 chip 互相重疊面積
            .font(.system(size: max(11, bh * 0.55), weight: .semibold))
            .foregroundStyle(.black)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            // chip 寬度跟譯文長度走，最小 max(bw, 40) 讓短字也好點（v1.2.9：50→40）
            .frame(minWidth: max(bw, 40), alignment: .leading)
            .fixedSize(horizontal: true, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.2), radius: 1.5, x: 0, y: 1)
            )
            .position(x: bx + bw / 2, y: by + bh / 2)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    selectedId = region.id
                }
            }
    }

    /// v1.2.7：被點選的塊放大顯示，原文 + 譯文並列，蓋過鄰近 chip
    @ViewBuilder
    private func popoverView(
        region: OCRRegion, translated: String,
        viewSize: CGSize,
        offsetX: CGFloat, offsetY: CGFloat,
        drawnSize: CGSize
    ) -> some View {
        let bx = offsetX + region.boundingBox.minX * drawnSize.width
        let by = offsetY + region.boundingBox.minY * drawnSize.height
        let bw = region.boundingBox.width * drawnSize.width
        let bh = region.boundingBox.height * drawnSize.height
        let maxW = min(viewSize.width * 0.85, 320)
        let estHeight: CGFloat = 130
        // 偏好下方；下方空間不夠則放上方
        let popCenterY: CGFloat = {
            if by + bh + 6 + estHeight < viewSize.height {
                return by + bh + 6 + estHeight / 2
            } else {
                return max(estHeight / 2 + 8, by - 6 - estHeight / 2)
            }
        }()

        VStack(alignment: .leading, spacing: 6) {
            Text(region.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.gray)
                .lineLimit(3)
            Divider().opacity(0.5)
            Text(translated)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .lineLimit(6)
            Text("點此或別處關閉")
                .font(.system(size: 10))
                .foregroundStyle(.gray.opacity(0.7))
        }
        .padding(10)
        .frame(width: maxW, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        )
        .position(
            x: max(maxW / 2 + 8, min(viewSize.width - maxW / 2 - 8, bx + bw / 2)),
            y: popCenterY
        )
        .zIndex(100)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedId = nil
            }
        }
    }
}

// MARK: - FullscreenZoomableImage (v1.2.5)

/// 全螢幕可縮放疊圖檢視。
/// 互動：
/// - Pinch zoom（1x ~ 5x）
/// - Drag pan（縮放後）
/// - Double tap：在 1x / 2.5x 之間切換
/// - 右上 X 關閉
private struct FullscreenZoomableImage: View {
    let image: UIImage
    let regions: [OCRRegion]
    let showOverlay: Bool
    let onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ImageWithOverlayInternal(
                image: image,
                regions: regions,
                showOverlay: showOverlay
            )
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(maxScale, max(minScale, lastScale * value))
                    }
                    .onEnded { _ in lastScale = scale }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    if scale > 1.1 {
                        scale = 1.0; lastScale = 1.0
                        offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2.5; lastScale = 2.5
                    }
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                    .accessibilityLabel("關閉全螢幕")
                }
                Spacer()
                Text("捏合縮放 ／ 拖曳平移 ／ 雙擊切換 1x↔2.5x")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
            }
        }
    }
}

/// 內部用：把 ImageWithOverlay 邏輯獨立出來，避免 nesting view body
/// 這支跟主 ImageWithOverlay 一樣，差別只是不夾 outer aspectRatio modifier
/// （fullscreen 自己處理 layout）
private struct ImageWithOverlayInternal: View {
    let image: UIImage
    let regions: [OCRRegion]
    let showOverlay: Bool

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let imgSize = image.size
            let scale = min(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
            let drawnSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let offsetX = (viewSize.width - drawnSize.width) / 2
            let offsetY = (viewSize.height - drawnSize.height) / 2

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: viewSize.width, height: viewSize.height)

                if showOverlay {
                    ForEach(regions) { region in
                        if let translated = region.translatedText, !translated.isEmpty {
                            let bx = offsetX + region.boundingBox.minX * drawnSize.width
                            let by = offsetY + region.boundingBox.minY * drawnSize.height
                            let bw = region.boundingBox.width * drawnSize.width
                            let bh = region.boundingBox.height * drawnSize.height

                            Text(translated)
                                .font(.system(size: max(13, bh * 0.7), weight: .semibold))
                                .foregroundStyle(.black)
                                .lineLimit(3)
                                .minimumScaleFactor(0.5)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .frame(minWidth: max(bw, 50), alignment: .leading)
                                .fixedSize(horizontal: true, vertical: true)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.95))
                                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                )
                                .position(x: bx + bw / 2, y: by + bh / 2)
                        }
                    }
                }
            }
        }
        .aspectRatio(image.size, contentMode: .fit)
    }
}

// MARK: - LanguageChip

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

// MARK: - CameraPicker（UIImagePickerController SwiftUI wrapper）

private struct CameraPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage?) -> Void
        init(onPicked: @escaping (UIImage?) -> Void) { self.onPicked = onPicked }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            let image = (info[.originalImage] as? UIImage)
            onPicked(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPicked(nil)
        }
    }
}

#Preview {
    NavigationStack { PhotoTranslationView() }
        .environmentObject(AppDependencies.makeMock())
}
