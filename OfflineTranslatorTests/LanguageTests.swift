import XCTest
@testable import OfflineTranslator

final class LanguageTests: XCTestCase {

    // MARK: - Supported pairs (MVP 縮減範圍後只剩中⇄英)

    func test_supportedPairs_haveMVPCoverage() {
        // MVP v0.1 只做繁中 ⇄ 英文，共 2 對
        XCTAssertEqual(LanguagePair.supported.count, 2)
        XCTAssertTrue(LanguagePair.supported.contains(
            .init(source: .traditionalChinese, target: .english)
        ))
        XCTAssertTrue(LanguagePair.supported.contains(
            .init(source: .english, target: .traditionalChinese)
        ))
    }

    func test_unsupportedPairs_areFlagged() {
        // 同語言互譯不在支援清單
        let enEn = LanguagePair(source: .english, target: .english)
        XCTAssertFalse(enEn.isSupported)

        let zhZh = LanguagePair(source: .traditionalChinese, target: .traditionalChinese)
        XCTAssertFalse(zhZh.isSupported)
    }

    // MARK: - BCP-47

    func test_bcp47_matchesExpectedValues() {
        XCTAssertEqual(Language.traditionalChinese.bcp47, "zh-Hant")
        XCTAssertEqual(Language.english.bcp47, "en")
    }

    // MARK: - Enum completeness

    func test_allCases_hasExactlyTwoLanguages() {
        // 縮減範圍後只應該有兩種語言；若新增請同步更新此測試
        XCTAssertEqual(Language.allCases.count, 2)
        XCTAssertTrue(Language.allCases.contains(.traditionalChinese))
        XCTAssertTrue(Language.allCases.contains(.english))
    }
}
