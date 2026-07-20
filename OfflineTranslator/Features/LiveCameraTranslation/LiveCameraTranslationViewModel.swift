import Foundation
import SwiftUI
import AVFoundation

/// v1.4.0：即時鏡頭翻譯 ViewModel。
///
/// 職責：
/// - 相機權限流程
/// - service 生命週期（start / stop 綁 view 的 appear / disappear）
/// - 訂閱 regionStream，把結果丟給 View
/// - 語言切換（reuse v1.3.0 的 LanguagePickerChip）
/// - 監聽 `ProcessInfo.thermalState`，發燙時自動降 fps 並提示使用者
@MainActor
final class LiveCameraTranslationViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case noPermission
        case starting
        case running
        case failed(String)
    }

    // MARK: - Published

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var regions: [RecognizedTextRegion] = []
    @Published private(set) var isPaused = false
    @Published private(set) var isThermallyThrottled = false
    /// 進場後一段時間都沒辨識到文字 → 顯示「對準文字試試」
    @Published private(set) var showsAimHint = false

    @Published var sourceLanguage: Language {
        didSet { Task { await applyLanguageChange() } }
    }
    @Published var targetLanguage: Language {
        didSet { Task { await applyLanguageChange() } }
    }

    // MARK: - Deps

    private let service: LiveCameraTranslationService
    private let permissions = PermissionManager()

    private var streamTask: Task<Void, Never>?
    private var thermalObserver: NSObjectProtocol?
    private var hintTask: Task<Void, Never>?

    var captureSession: AVCaptureSession? { service.captureSession }

    var currentPair: LanguagePair {
        .init(source: sourceLanguage, target: targetLanguage)
    }

    /// 可選的目標語言（排除來源本身）
    var availableTargets: [Language] {
        Language.allCases.filter { $0 != sourceLanguage }
    }

    // MARK: - Init

    init(service: LiveCameraTranslationService,
         source: Language = .english,
         target: Language = .traditionalChinese) {
        self.service = service
        self.sourceLanguage = source
        self.targetLanguage = target
    }

    // MARK: - Lifecycle

    func onAppear() async {
        guard phase == .idle || phase == .noPermission || isFailed else { return }

        // 1. 相機權限
        var status = permissions.status(for: .camera)
        if status == .notDetermined {
            phase = .requestingPermission
            status = await permissions.request(.camera)
        }
        guard status == .granted else {
            phase = .noPermission
            return
        }

        // 2. 啟動 capture
        phase = .starting
        do {
            try await service.start()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            return
        }

        // 3. 訂閱結果
        subscribeStream()
        startThermalMonitoring()
        scheduleAimHint()
        phase = .running
    }

    func onDisappear() {
        streamTask?.cancel(); streamTask = nil
        hintTask?.cancel(); hintTask = nil
        if let obs = thermalObserver {
            NotificationCenter.default.removeObserver(obs)
            thermalObserver = nil
        }
        service.stop()
        regions = []
        isPaused = false
        phase = .idle
    }

    // MARK: - Actions

    func togglePause() {
        isPaused.toggle()
        service.setPaused(isPaused)
        if !isPaused { scheduleAimHint() }
    }

    func swapLanguages() {
        let old = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = old
    }

    func setSource(_ lang: Language) {
        guard lang != sourceLanguage else { return }
        sourceLanguage = lang
        if targetLanguage == lang {
            targetLanguage = availableTargets.first ?? .traditionalChinese
        }
    }

    func setTarget(_ lang: Language) {
        guard lang != targetLanguage, lang != sourceLanguage else { return }
        targetLanguage = lang
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Private

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func subscribeStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await batch in self.service.regionStream {
                if Task.isCancelled { return }
                self.regions = batch
                if !batch.isEmpty { self.showsAimHint = false }
            }
        }
    }

    private func applyLanguageChange() async {
        regions = []
        await service.setLanguagePair(currentPair)
        scheduleAimHint()
    }

    /// 5 秒內沒辨識到任何文字就給提示（v1.2.0 設計文件的 UX 細節）
    private func scheduleAimHint() {
        hintTask?.cancel()
        showsAimHint = false
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.regions.isEmpty && !self.isPaused {
                self.showsAimHint = true
            }
        }
    }

    private func startThermalMonitoring() {
        applyThermalState(ProcessInfo.processInfo.thermalState)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            Task { @MainActor in self?.applyThermalState(state) }
        }
    }

    private func applyThermalState(_ state: ProcessInfo.ThermalState) {
        let shouldThrottle = (state == .serious || state == .critical)
        guard shouldThrottle != isThermallyThrottled else { return }
        isThermallyThrottled = shouldThrottle
        service.setThermallyThrottled(shouldThrottle)
    }
}
