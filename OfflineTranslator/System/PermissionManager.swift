import Foundation
import AVFoundation
import Speech
import Photos

/// 集中處理權限請求 / 狀態查詢的小幫手。
/// 把 Apple 一堆風格不一致的 API 包成統一的 async 介面。
enum AppPermission {
    case microphone
    case speechRecognition
    case camera
    case photoLibrary
}

enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

struct PermissionManager {

    func status(for permission: AppPermission) -> PermissionStatus {
        switch permission {
        case .microphone:
            return Self.map(AVAudioApplication.shared.recordPermission)
        case .speechRecognition:
            return Self.map(SFSpeechRecognizer.authorizationStatus())
        case .camera:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .photoLibrary:
            return Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        }
    }

    @discardableResult
    func request(_ permission: AppPermission) async -> PermissionStatus {
        switch permission {
        case .microphone:
            return await withCheckedContinuation { c in
                AVAudioApplication.requestRecordPermission { granted in
                    c.resume(returning: granted ? .granted : .denied)
                }
            }
        case .speechRecognition:
            return await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { status in
                    c.resume(returning: Self.map(status))
                }
            }
        case .camera:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .granted : .denied
        case .photoLibrary:
            return await withCheckedContinuation { c in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    c.resume(returning: Self.map(status))
                }
            }
        }
    }

    // MARK: - Mapping

    private static func map(_ status: AVAudioApplication.recordPermission) -> PermissionStatus {
        switch status {
        case .undetermined: return .notDetermined
        case .granted:      return .granted
        case .denied:       return .denied
        @unknown default:   return .denied
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized:    return .granted
        case .denied, .restricted: return .denied
        @unknown default:    return .denied
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized:    return .granted
        case .denied, .restricted: return .denied
        @unknown default:    return .denied
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized, .limited: return .granted
        case .denied, .restricted:  return .denied
        @unknown default:           return .denied
        }
    }
}
