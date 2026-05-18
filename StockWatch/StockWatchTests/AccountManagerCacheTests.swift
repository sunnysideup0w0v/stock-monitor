import XCTest
@testable import StockWatch

/// AccountManager.connectedAccountIds 캐싱 동작 및 fetchDistinctValues SQL 안전성 검증.
/// R8(AccountManager 캐싱), R5(DB 에러 처리)의 안전망.
@MainActor
final class AccountManagerCacheTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AccountManager.invalidateCache()
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
        KeychainHelper.delete(account: KeychainKey.kiwoomAppKey)
    }

    override func tearDown() async throws {
        AccountManager.invalidateCache()
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
        KeychainHelper.delete(account: KeychainKey.kiwoomAppKey)
        try await super.tearDown()
    }

    // MARK: - connectedAccountIds 캐싱

    func test_connectedAccountIds_cachedAfterFirstRead() {
        // 첫 번째 읽기 → Keychain 조회 후 캐싱
        let first = AccountManager.connectedAccountIds

        // Keychain에 직접 써도 캐시가 있으면 반영 안 됨
        KeychainHelper.save("CACHEDKEY", account: KeychainKey.kisAppKey)
        let second = AccountManager.connectedAccountIds

        XCTAssertEqual(first, second, "캐시가 유효할 때는 Keychain 변경이 반영되지 않아야 함")

        // 정리
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
    }

    func test_invalidateCache_causesRereading() {
        // 초기 상태 — KIS 없음
        let before = AccountManager.connectedAccountIds
        XCTAssertFalse(before.contains(where: { $0.hasPrefix("KIS-") }))

        // Keychain에 직접 저장 후 캐시 무효화
        KeychainHelper.save("FRESHKEY1", account: KeychainKey.kisAppKey)
        AccountManager.invalidateCache()

        let after = AccountManager.connectedAccountIds
        XCTAssertTrue(after.contains(where: { $0.hasPrefix("KIS-") }),
                      "invalidateCache 후에는 새로 쓴 Keychain 값이 반영돼야 함")
    }

    func test_connectedAccountIds_emptyWhenNoCredentials() {
        // 테스트 환경에서는 Keychain이 비어 있음 (setUp에서 삭제)
        // testAccountId 오버라이드가 없을 때
        guard AccountManager.testAccountId == nil else {
            // testAccountId 오버라이드 중이면 이 테스트는 의미 없으므로 스킵
            return
        }
        let ids = AccountManager.connectedAccountIds
        XCTAssertFalse(ids.contains(where: { $0.hasPrefix("KIS-") }),
                       "KIS Keychain이 없으면 KIS- 계정이 목록에 없어야 함")
        XCTAssertFalse(ids.contains(where: { $0.hasPrefix("KIWOOM-") }),
                       "Kiwoom Keychain이 없으면 KIWOOM- 계정이 목록에 없어야 함")
    }

    func test_connectedAccountIds_multiplebrokers() {
        KeychainHelper.save("KISKEY001", account: KeychainKey.kisAppKey)
        KeychainHelper.save("KIWOOMK1", account: KeychainKey.kiwoomAppKey)
        AccountManager.invalidateCache()

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
        // 결과가 [String]이며 크래시 없이 반환됨을 검증 (stock_universe가 비어도 통과)
        XCTAssertNotNil(sectors)
    }
}
