import XCTest
@testable import StockWatch

/// AccountManager.connectedAccountIds 갱신 동작 및 fetchDistinctValues SQL 안전성 검증.
/// R8(AccountManager @MainActor class 전환), R5(DB 에러 처리)의 안전망.
@MainActor
final class AccountManagerCacheTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
        KeychainHelper.delete(account: KeychainKey.kiwoomAppKey)
        AccountManager.shared.refresh()
    }

    override func tearDown() async throws {
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
        KeychainHelper.delete(account: KeychainKey.kiwoomAppKey)
        AccountManager.shared.refresh()
        try await super.tearDown()
    }

    // MARK: - connectedAccountIds 갱신

    func test_connectedAccountIds_notUpdatedWithoutRefresh() {
        // refresh() 없이 Keychain을 직접 써도 published 값은 바뀌지 않음
        let before = AccountManager.connectedAccountIds

        KeychainHelper.save("PENDINGKEY", account: KeychainKey.kisAppKey)
        let after = AccountManager.connectedAccountIds

        XCTAssertEqual(before, after, "refresh() 호출 전에는 Keychain 변경이 반영되지 않아야 함")

        // 정리
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
    }

    func test_refresh_updatesConnectedAccountIds() {
        // 초기 상태 — KIS 없음
        let before = AccountManager.connectedAccountIds
        XCTAssertFalse(before.contains(where: { $0.hasPrefix("KIS-") }))

        KeychainHelper.save("FRESHKEY1", account: KeychainKey.kisAppKey)
        AccountManager.shared.refresh()

        let after = AccountManager.connectedAccountIds
        XCTAssertTrue(after.contains(where: { $0.hasPrefix("KIS-") }),
                      "refresh() 후에는 새로 쓴 Keychain 값이 반영돼야 함")
    }

    func test_connectedAccountIds_emptyWhenNoCredentials() {
        guard AccountManager.testAccountId == nil else { return }
        let ids = AccountManager.connectedAccountIds
        XCTAssertFalse(ids.contains(where: { $0.hasPrefix("KIS-") }),
                       "KIS Keychain이 없으면 KIS- 계정이 목록에 없어야 함")
        XCTAssertFalse(ids.contains(where: { $0.hasPrefix("KIWOOM-") }),
                       "Kiwoom Keychain이 없으면 KIWOOM- 계정이 목록에 없어야 함")
    }

    func test_connectedAccountIds_multipleBrokers() {
        KeychainHelper.save("KISKEY001", account: KeychainKey.kisAppKey)
        KeychainHelper.save("KIWOOMK1", account: KeychainKey.kiwoomAppKey)
        AccountManager.shared.refresh()

        let ids = AccountManager.connectedAccountIds
        XCTAssertTrue(ids.contains(where: { $0.hasPrefix("KIS-") }))
        XCTAssertTrue(ids.contains(where: { $0.hasPrefix("KIWOOM-") }))
        XCTAssertEqual(ids.count, 2)
    }

    // MARK: - displayName

    func test_displayName_kis() {
        XCTAssertEqual(AccountManager.displayName(for: "KIS-ABCDEF12"), "KIS")
    }

    func test_displayName_kiwoom() {
        XCTAssertEqual(AccountManager.displayName(for: "KIWOOM-ABCDEF12"), "키움")
    }

    func test_displayName_unknown() {
        XCTAssertEqual(AccountManager.displayName(for: "UNKNOWN-123"), "UNKNOWN-123")
    }

    // MARK: - fetchDistinctValues 타입 안전성 (UniverseColumn 열거형)

    func test_fetchDistinctValues_sector_doesNotThrow() {
        XCTAssertNoThrow(try DatabaseManager.shared.fetchDistinctValues(column: .sector),
                         "sector 컬럼 조회는 예외를 던지지 않아야 함")
    }

    func test_fetchDistinctValues_market_doesNotThrow() {
        XCTAssertNoThrow(try DatabaseManager.shared.fetchDistinctValues(column: .market),
                         "market 컬럼 조회는 예외를 던지지 않아야 함")
    }

    func test_fetchDistinctValues_returnsStrings() throws {
        let sectors = try DatabaseManager.shared.fetchDistinctValues(column: .sector)
        XCTAssertNotNil(sectors)
    }
}
