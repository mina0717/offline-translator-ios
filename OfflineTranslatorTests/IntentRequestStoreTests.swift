import XCTest
@testable import OfflineTranslator

/// v1.1.1 fix：IntentRequestStore 從單 slot 升級成 FIFO queue 後，
/// 驗證多筆 submit 不會掉訊息、drainAll 能一次清空。
@MainActor
final class IntentRequestStoreTests: XCTestCase {

    var store: IntentRequestStore!

    override func setUp() async throws {
        try await super.setUp()
        store = IntentRequestStore.shared
        // 確保每個測試都從乾淨狀態開始（避免其他測試殘留）
        _ = store.drainAll()
    }

    override func tearDown() async throws {
        _ = store.drainAll()
        try await super.tearDown()
    }

    // MARK: - Basic queue behavior

    func test_submit_singleRequest_queueContainsOne() {
        store.submit(.translateText(text: "hello", target: .traditionalChinese))

        XCTAssertEqual(store.queue.count, 1)
        if case .translateText(let text, let target) = store.nextPending {
            XCTAssertEqual(text, "hello")
            XCTAssertEqual(target, .traditionalChinese)
        } else {
            XCTFail("expected .translateText at queue head")
        }
    }

    func test_submit_twoRequests_bothPreserved_FIFO() {
        store.submit(.translateText(text: "first", target: .english))
        store.submit(.translateClipboard(target: .traditionalChinese))

        XCTAssertEqual(store.queue.count, 2)

        guard case .translateText(let text1, _) = store.consume() else {
            return XCTFail("expected translateText at head")
        }
        XCTAssertEqual(text1, "first")

        guard case .translateClipboard(let target) = store.consume() else {
            return XCTFail("expected translateClipboard next")
        }
        XCTAssertEqual(target, .traditionalChinese)

        XCTAssertNil(store.consume())
    }

    // MARK: - Regression: previously single-slot dropped the first

    /// 這個 test 是專門防 v1.1 的 regression：
    /// 先前 `pending` 是單 slot，第二次 submit 會覆蓋第一筆，第一筆變成孤兒。
    /// 現在改 queue 後兩筆都要能被 consume 到。
    func test_submit_rapidDouble_firstNotLost() {
        store.submit(.translateText(text: "keep-me", target: .english))
        store.submit(.translateText(text: "and-me", target: .english))

        guard case .translateText(let firstText, _) = store.consume() else {
            return XCTFail("expected first submit to survive")
        }
        XCTAssertEqual(firstText, "keep-me",
                       "regression: single-slot store would have dropped this")

        guard case .translateText(let secondText, _) = store.consume() else {
            return XCTFail("expected second submit to survive")
        }
        XCTAssertEqual(secondText, "and-me")
    }

    // MARK: - drainAll

    func test_drainAll_returnsAllInOrderAndEmptiesQueue() {
        store.submit(.translateText(text: "a", target: .english))
        store.submit(.translateText(text: "b", target: .english))
        store.submit(.translateClipboard(target: .traditionalChinese))

        let drained = store.drainAll()

        XCTAssertEqual(drained.count, 3)
        XCTAssertTrue(store.queue.isEmpty)
        XCTAssertNil(store.nextPending)

        // Order preserved
        if case .translateText(let t, _) = drained[0] {
            XCTAssertEqual(t, "a")
        } else { XCTFail("slot 0") }
        if case .translateText(let t, _) = drained[1] {
            XCTAssertEqual(t, "b")
        } else { XCTFail("slot 1") }
        if case .translateClipboard = drained[2] {
            // ok
        } else { XCTFail("slot 2") }
    }

    func test_drainAll_onEmpty_returnsEmpty() {
        let drained = store.drainAll()
        XCTAssertTrue(drained.isEmpty)
    }

    // MARK: - consume on empty

    func test_consume_onEmpty_returnsNil() {
        XCTAssertNil(store.consume())
    }
}
