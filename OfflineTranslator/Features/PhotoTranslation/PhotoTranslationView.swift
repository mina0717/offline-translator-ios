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
                // v1.2.5：放大顯示區（用圖片自身比例 + 提高最大高度），疊圖文字字級放大
                ImageWithOverlay(
                    image: image,
                    regions: vm.regions,
                    showOverlay: vm.displayMode == .overlay && vm.phase == .done
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 320, maxHeight: 560)
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

        private var actionButtons: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    showCamera = true
                    CameraTip.hasUsedCameraOnce = true
                } label: {
                    Label("相機", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .disabled(vm.isProcessing)
                .popoverTip(cameraTip)

                PhotosPicker(
                    selection: $photoPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("相簿", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
                .disabled(vm.isProcessing)

                if vm.pickedImage != nil {
                    Button {
                        vm.clear()
                    } label: {
                        Image(systemName: "xmark")
                            .padding(.vertical, Theme.Spacing.sm)
                            .padding(.horizontal, Theme.Spacing.md)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
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
/// 計算流程：
/// 1. 用 GeometryReader 拿到顯示區大小
/// 2. 算出 Image 真正被縮到的尺寸（aspect fit），居中
/// 3. region.boundingBox 是 0-1 normalized，乘上實際圖尺寸 + offset = view 座標
private struct ImageWithOverlay: View {
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

                            // 譯文 chip：白底覆蓋原文。v1.2.5 字級放大、寬度允許溢出
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
