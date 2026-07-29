import Foundation

/// v1.5.0：免持辨識的假實作。
/// Preview 與測試用 —— 沒有麥克風，定時吐出幾句假的辨識結果。
@MainActor
final class HandsFreeASRServiceMock: HandsFreeASRService {

    var events: AsyncStream<HandsFreeASREvent> { activeStream }
    private var activeStream: AsyncStream<HandsFreeASREvent>!
    private var continuation: AsyncStream<HandsFreeASREvent>.Continuation?

    private var tickTask: Task<Void, Never>?

    /// 假資料：模擬「逐字浮現 → 定案」的過程
    private let scripts = [
        "Where is the train station",
        "How much does this cost",
        "Could you say that again please"
    ]

    init() { rearm() }

    private func rearm() {
        continuation?.finish()
        var cont: AsyncStream<HandsFreeASREvent>.Continuation!
        activeStream = AsyncStream { cont = $0 }
        continuation = cont
    }

    func start(language: Language) async throws {
        rearm()
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            guard let self else { return }
            var index = 0
            while !Task.isCancelled {
                let line = self.scripts[index % self.scripts.count]
                index += 1

                self.continuation?.yield(.speechStarted)
                // 逐字浮現，模擬 partial
                var built = ""
                for word in line.split(separator: " ") {
                    if Task.isCancelled { return }
                    built += (built.isEmpty ? "" : " ") + word
                    self.continuation?.yield(.partial(built))
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                if Task.isCancelled { return }
                self.continuation?.yield(.finalized(line))
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        continuation?.finish()
        continuation = nil
    }

    func supportsOnDevice(_ language: Language) -> Bool { true }
}
