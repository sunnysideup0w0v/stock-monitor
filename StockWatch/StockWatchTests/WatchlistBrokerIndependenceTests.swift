import XCTest
@testable import StockWatch

/// 관심종목이 브로커에 독립적으로 동작하는지 검증.
/// v13 마이그레이션(accountId = "USER")과 fetchWatchlist isAnyConnected 가드 동작 확인.
final class WatchlistBrokerIndependenceTests: XCTestCase {

    private let prefix   = "ZWATCH_"
    private let accountA = "TEST-WATCH-BROKER-A"
    private let accountB = "TEST-WATCH-BROKER-B"

    override func setUp() async throws {
        try await super.setUp()
        AccountManager.testAccountId = accountA
        let pfx = prefix
        await MainActor.run { cleanupWatchlist(prefix: pfx) }
    }

    override func tearDown() async throws {
        let pfx = prefix
        await MainActor.run { cleanupWatchlist(prefix: pfx) }
        AccountManager.testAccountId = nil
        try await super.tearDown()
    }

    // MARK: - accountId 항상 "USER"

    @MainActor func test_insert_alwaysSetsUserAccountId_regardlessOfBroker() throws {
        AccountManager.testAccountId = accountA
        var item = WatchlistItem(id: nil, symbol: prefix + "W1", name: "A계정삽입", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)
        XCTAssertEqual(item.accountId, "USER")
    }

    @MainActor func test_insert_withBrokerBAccountId_stillSetsUser() throws {
        AccountManager.testAccountId = accountB
        var item = WatchlistItem(id: nil, symbol: prefix + "W2", name: "B계정삽입", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)
        XCTAssertEqual(item.accountId, "USER",
                       "accountId는 브로커에 관계없이 항상 'USER'여야 함")
    }

    // MARK: - 브로커 전환 후에도 관심종목 유지

    @MainActor func test_watchlistSurvivesBrokerSwitch_fromAToB() throws {
        AccountManager.testAccountId = accountA
        var item = WatchlistItem(id: nil, symbol: prefix + "W3", name: "스위치테스트", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)

        // 브로커 B로 전환
        AccountManager.testAccountId = accountB
        let items = try DatabaseManager.shared.fetchWatchlist()
        XCTAssertTrue(items.contains(where: { $0.symbol == prefix + "W3" }),
                      "브로커 전환 후에도 관심종목이 보여야 함")
    }

    // MARK: - 연결된 브로커가 있으면 노출

    @MainActor func test_watchlist_visibleWhenAnyBrokerConnected() throws {
        var item = WatchlistItem(id: nil, symbol: prefix + "W4", name: "가시성테스트", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)

        // testAccountId = accountA → isAnyConnected = true
        AccountManager.testAccountId = accountA
        let items = try DatabaseManager.shared.fetchWatchlist()
        XCTAssertTrue(items.contains(where: { $0.symbol == prefix + "W4" }))
    }

    // MARK: - 연결된 브로커 없으면 빈 배열 (CI 전용)

    @MainActor func test_watchlist_hiddenWhenDisconnected_ciOnly() throws {
        var item = WatchlistItem(id: nil, symbol: prefix + "W5", name: "미연결테스트", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)

        // testAccountId = nil 로 전환 후 실제 Keychain 확인
        AccountManager.testAccountId = nil
        defer { AccountManager.testAccountId = accountA }

        // CI(클린 환경)에서만 확인; 개발 기기에 Keychain이 있으면 스킵
        if AccountManager.connectedAccountIds.isEmpty {
            let items = try DatabaseManager.shared.fetchWatchlist()
            XCTAssertFalse(items.contains(where: { $0.symbol == prefix + "W5" }),
                           "미연결 시 관심종목은 노출되지 않아야 함")
        }
    }

    // MARK: - update가 accountId를 변경하지 않음

    @MainActor func test_update_doesNotChangeAccountId() throws {
        var item = WatchlistItem(id: nil, symbol: prefix + "W6", name: "업데이트전", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)

        var updated = item
        updated.name = "업데이트후"
        updated.alias = "별칭"
        try DatabaseManager.shared.update(updated)

        let fetched = try DatabaseManager.shared.fetchWatchlist().first { $0.symbol == prefix + "W6" }
        XCTAssertEqual(fetched?.accountId, "USER", "update 후에도 accountId는 'USER'여야 함")
        XCTAssertEqual(fetched?.alias, "별칭")
    }

    // MARK: - delete 동작

    @MainActor func test_delete_removesItemFromFetch() throws {
        var item = WatchlistItem(id: nil, symbol: prefix + "W7", name: "삭제테스트", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)

        let before = try DatabaseManager.shared.fetchWatchlist()
        XCTAssertTrue(before.contains(where: { $0.symbol == prefix + "W7" }))

        try DatabaseManager.shared.delete(item)

        let after = try DatabaseManager.shared.fetchWatchlist()
        XCTAssertFalse(after.contains(where: { $0.symbol == prefix + "W7" }))
    }

    // MARK: - 중복 심볼 허용 검증 (DB 유니크 제약 없음)

    @MainActor func test_duplicateSymbol_bothInserted() throws {
        var item1 = WatchlistItem(id: nil, symbol: prefix + "W8", name: "중복1", alias: nil, group: .watchlist)
        var item2 = WatchlistItem(id: nil, symbol: prefix + "W8", name: "중복2", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item1)
        try DatabaseManager.shared.insert(&item2)

        let items = try DatabaseManager.shared.fetchWatchlist()
        let dups = items.filter { $0.symbol == prefix + "W8" }
        XCTAssertEqual(dups.count, 2, "DB에 유니크 제약이 없으므로 중복 삽입 허용")
    }
}

@MainActor
private func cleanupWatchlist(prefix: String) {
    guard let items = try? DatabaseManager.shared.fetchWatchlist() else { return }
    for item in items where item.symbol.hasPrefix(prefix) {
        try? DatabaseManager.shared.delete(item)
    }
}
