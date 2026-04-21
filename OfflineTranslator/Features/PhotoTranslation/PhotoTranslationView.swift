import SwiftUI
import UIKit      // UIImage, UIImagePickerController, UIPasteboard
import PhotosUI

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

        var body: some View {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    languageBar
                    imageCard
                    actionButtons
                    errorBanner
                    if !vm.recognizedLines.isEmpty {
                        recognizedCard
                    }
                    if !vm.translatedText.isEmpty {
                        translatedCard
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
                .disabled(vm.isProcessing)
                LanguageChip(language: vm.targetLanguage, caption: "譯文")
            }
        }

        @ViewBuilder
        private var imageCard: some View {
            if let image = vm.pickedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topTrailing) {
                        if vm.isProcessing {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.8)
                                Text("辨識翻譯中…")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(.white)
                            }
                            .padding(8)
                            .background(Capsule().fill(.black.opacity(0.5)))
                            .padding(8)
                        }
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
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .glassCard()
            }
        }

        private var actionButtons: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    showCamera = true
                } label: {
                    Label("相機", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .disabled(vm.isProcessing)

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

        private var recognizedCard: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("\(vm.sourceLanguage.flag) \(vm.sourceLanguage.displayName) · 辨識到 \(vm.recognizedLines.count) 行")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(vm.mergedRecognizedText)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .glassCard()
        }

        private var translatedCard: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("\(vm.targetLanguage.flag) \(vm.targetLanguage.displayName) · 譯文")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
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
                Text(vm.translatedText)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .glassCard()
        }
    }
}

// MARK: - LanguageChip（private 版本，與 SpeechTranslationView 獨立）

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
        // ⚠️ Mac 實測：模擬器沒有相機；.camera 會 crash
        // 因此若 sourceType 不可用就退回 .photoLibrary
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
