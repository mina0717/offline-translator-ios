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
    /// v1.4.0 hotfix2：整段啟動流程自己持有的 Task。
    /// **不能**靠 SwiftUI 的 `.task { }` 驅動 —— 那個會隨 view 更新被取消，
    /// 一旦在 await 權限請求時被砍掉，流程就永遠停在半路（這正是 build #53 的症狀）。
    private var startupTask: Task<Void, Never>?
    /// 啟動看門狗。**涵蓋整段流程**（權限 + capture 啟動），不是只有 start()。
    private var startWatchdog: Task<Void, Never>?
    private static let startTimeoutSeconds: UInt64 = 10

    var captureSession: AVCaptureSession? { service.captureSession }

    var currentPair: LanguagePair {
        .init(source: sourceLanguage, target: targetLanguage)
    }

    /// 可選的目標語言（排除來源本身）
    var availableTargets: [Language] {
        Language.allCases.filter { $0 != sourceLanguage }
    }

    /// v1.4.0 hotfix3：有辨識到文字、但一句都翻不出來。
    /// 通常是語言包還沒下載完；不講出來的話畫面上只會是一堆黃框，使用者不知道發生什麼事。
    var hasTextButNoTranslation: Bool {
        !regions.isEmpty && regions.allSatisfy { $0.translatedText == nil }
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

    /// v1.4.0 hotfix2：由 View 的 `onAppear`（同步）呼叫。
    /// 啟動流程掛在自己的 Task 上，不受 SwiftUI view 更新 / `.task` 取消影響。
    func begin() {
        guard phase == .idle || phase == .noPermission || isFailed else { return }
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            await self?.runStartup()
        }
    }

    private func runStartup() async {
        // 看門狗**先**開，涵蓋整段流程。
        // build #53 的看門狗開在權限檢查之後，結果卡在權限那步時它根本沒被建立。
        startWatchdog?.cancel()
        startWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.startTimeoutSeconds * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            switch self.phase {
            case .requestingPermission, .starting:
                self.phase = .failed(self.timeoutMessage(for: self.phase))
            default:
                break
            }
        }
        defer { startWatchdog?.cancel(); startWatchdog = nil }

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
        guard !Task.isCancelled else { return }

        // 2. 啟動 capture
        phase = .starting
        do {
            try await service.start()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            return
        }

        // 看門狗可能已經把 phase 打到 .failed，別覆蓋掉錯誤畫面
        guard phase == .starting else { return }

        // 3. 訂閱結果
        subscribeStream()
        startThermalMonitoring()
        scheduleAimHint()
        phase = .running
    }

    /// 逾時訊息帶上卡住的階段，讓使用者回報時我們一眼就知道死在哪
    private func timeoutMessage(for phase: Phase) -> String {
        let base = LiveCameraError.startTimeout.errorDescription ?? ""
        let stage: String
        switch phase {
        case .requestingPermission: stage = String(localized: "live.stage.permission")
        case .starting:             stage = String(localized: "live.stage.camera")
        default:                    stage = ""
        }
        return stage.isEmpty ? base : "\(base)\n(\(stage))"
    }

    /// 從 .failed / .noPermission 重試
    func retry() {
        phase = .idle
        begin()
    }

    func onDisappear() {
        startupTask?.cancel(); startupTask = nil
        streamTask?.cancel(); streamTask = nil
        hintTask?.cancel(); hintTask = nil
        startWatchdog?.cancel(); startWatchdog = nil
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
