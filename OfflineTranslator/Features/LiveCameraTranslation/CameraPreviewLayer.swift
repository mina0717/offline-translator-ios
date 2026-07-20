import SwiftUI
import AVFoundation

/// v1.4.0：把 `AVCaptureVideoPreviewLayer` 包成 SwiftUI View。
///
/// session 為 nil 時（Mock / Preview）顯示深色底，避免 Preview 崩潰。
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    /// 用 layerClass 讓 preview layer 自動跟著 view 的 bounds，不用手動同步 frame。
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
