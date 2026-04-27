import Foundation
import SwiftUI

/// 語言包預下載器（v1.2.1 - simplified for compile debugging）
@MainActor
final class LanguagePackBootstrap: ObservableObject {

    @Published private(set) var phaseTag: Int = 0   // 0=idle 1=checking 2=downloading 3=done 4=failed
    @Published private(set) var currentPairText: String = ""
    @Published private(set) var failureMessage: String?
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = 2

    private var hasStarted = false

    func runIfNeeded(mtService: AppleMTService?) async {
        guard !hasStarted else { return }
        hasStarted = true

        guard let mt = mtService else {
            phaseTag = 0
            return
        }

        completedCount = 0
        let pairs: [LanguagePair] = [
            LanguagePair(source: .traditionalChinese, target: .english),
            LanguagePair(source: .english, target: .traditionalChinese)
        ]

        for pair in pairs {
            phaseTag = 1
            currentPairText = "\(pair.source.displayName) → \(pair.target.displayName)"

            let status: LanguagePackStatus
            do {
                status = try await mt.languagePackStatus(for: pair)
            } catch {
                phaseTag = 4
                failureMessage = "檢查語言包狀態失敗：\(error.localizedDescription)"
                return
            }

            if status == .ready {
                completedCount += 1
                continue
            }

            phaseTag = 2
            do {
                try await mt.downloadLanguagePack(for: pair)
            } catch {
                if error is CancellationError {
                    completedCount += 1
                    continue
                }
                phaseTag = 4
                failureMessage = "下載語言包失敗：\(error.localizedDescription)"
                return
            }
            completedCount += 1
        }

        phaseTag = 3
    }

    func retry(mtService: AppleMTService?) async {
        hasStarted = false
        phaseTag = 0
        await runIfNeeded(mtService: mtService)
    }

    var isWorking: Bool { phaseTag == 1 || phaseTag == 2 }
    var isDone: Bool { phaseTag == 3 }

    var bannerMessage: String? {
        switch phaseTag {
        case 1:  return "正在檢查語言包：\(currentPairText)"
        case 2:  return "首次下載語言包中：\(currentPairText)（約需 1-3 分鐘）"
        case 4:  return failureMessage
        default: return nil
        }
    }
}
