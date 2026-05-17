import XCTest
@testable import StockWatch

/// DatabaseManager의 CRUD 동작 및 accountId 자동 설정 패턴을 검증한다.
/// 리팩토링(R2 BrokerSessionManager 추출, R5 에러 처리 개선)의 안전망 역할.
///
/// 모든 테스트는 "ZTEST_" 접두사 심볼을 사용해 실 데이터와 구분하며 tearDown에서 정리한다.
final class DatabaseManagerCRUDTests: XCTestCase {

    private let accountA = "TEST-CRUD-BROKER-A"
    private let accountB = "TEST-CRUD-BROKER-B"
    private let prefix   = "ZTEST_"

    override func setUp() async throws {
        try await super.setUp()
        AccountManager.testAccountId = accountA
        let pfx = prefix
        let acctA = accountA
        let acctB = accountB
        await MainActor.run { cleanup(prefix: pfx, accountIds: [acctA, acctB]) }
    }

    override func tearDown() async throws {
        let pfx = prefix
        let acctA = accountA
        let acctB = accountB
        await MainActor.run { cleanup(prefix: pfx, accountIds: [acctA, acctB]) }
        AccountManager.testAccountId = nil
        try await super.tearDown()
    }

    // MARK: - Watchlist: insert → accountId 자동 설정

    @MainActor func test_insertWatchlist_setsAccountIdFromManager() throws {
        let symbol = prefix + "WATCH1"
        var item = WatchlistItem(id: nil, symbol: symbol, name: "테스트종목", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)

        let fetched = try DatabaseManager.shared.fetchWatchlist().first { $0.symbol == symbol }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.accountId, accountA,
                       "insert()는 AccountManager.currentAccountId를 accountId로 자동 설정해야 함")
    }

    @MainActor func test_insertWatchlist_assignsRowId() throws {
        let symbol = prefix + "WATCH2"
        var item = WatchlistItem(id: nil, symbol: symbol, name: "ID확인", alias: nil, group: .watchlist)
        XCTAssertNil(item.id, "삽입 전 id는 nil")
        try DatabaseManager.shared.insert(&item)
        XCTAssertNotNil(item.id, "삽입 후 id가 할당돼야 함")
    }

    // MARK: - Watchlist: 미연결 시 빈 배열 (CI 전용)

    @MainActor func test_fetchWatchlist_whenDisconnected_returnsEmpty() throws {
        let symbol = prefix + "WATCH3"
        var item = WatchlistItem(id: nil, symbol: symbol, name: "연결확인", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&item)

        AccountManager.testAccountId = nil
        defer { AccountManager.testAccountId = accountA }

        // testAccountId = nil → connectedAccountIds가 실제 Keychain을 읽음
        // CI(클린 환경)에서만 결정론적으로 빈 배열; 개발 기기에선 스킵
        if AccountManager.connectedAccountIds.isEmpty {
            let result = try DatabaseManager.shared.fetchWatchlist()
            XCTAssertTrue(result.isEmpty,
                          "연결된 계좌가 없으면 fetchWatchlist()는 빈 배열을 반환해야 함")
        }
    }

    // MARK: - Portfolio: 브로커별 필터

    @MainActor func test_fetchPortfolio_for_filtersToSingleBroker() throws {
        let symA = prefix + "PORTA1"
        let symB = prefix + "PORTB1"

        // A 계좌 항목 삽입
        AccountManager.testAccountId = accountA
        var itemA = PortfolioItem(id: nil, symbol: symA, name: "A종목", averagePrice: 10_000, quantity: 1)
        try DatabaseManager.shared.insert(&itemA)

        // B 계좌 항목 삽입
        AccountManager.testAccountId = accountB
        var itemB = PortfolioItem(id: nil, symbol: symB, name: "B종목", averagePrice: 20_000, quantity: 2)
        try DatabaseManager.shared.insert(&itemB)

        AccountManager.testAccountId = accountA

        let forA = try DatabaseManager.shared.fetchPortfolio(for: accountA)
        XCTAssertTrue(forA.contains(where:  { $0.symbol == symA }))
        XCTAssertFalse(forA.contains(where: { $0.symbol == symB }))

        let forB = try DatabaseManager.shared.fetchPortfolio(for: accountB)
        XCTAssertTrue(forB.contains(where:  { $0.symbol == symB }))
        XCTAssertFalse(forB.contains(where: { $0.symbol == symA }))
    }

    @MainActor func test_insertPortfolio_setsAccountIdFromManager() throws {
        let sym = prefix + "PORTA2"
        AccountManager.testAccountId = accountB
        var item = PortfolioItem(id: nil, symbol: sym, name: "계정확인", averagePrice: 5_000, quantity: 3)
        try DatabaseManager.shared.insert(&item)

        let fetched = try DatabaseManager.shared.fetchPortfolio(for: accountB).first { $0.symbol == sym }
        XCTAssertEqual(fetched?.accountId, accountB)

        AccountManager.testAccountId = accountA
    }

    // MARK: - AlertCondition: recordAlertFired 원자성

    @MainActor func test_recordAlertFired_insertsHistoryAndUpdatesCondition() throws {
        let sym = prefix + "COND01"
        var condition = AlertCondition(
            id: nil, symbol: sym, triggerType: .targetPrice, threshold: 70_000,
            isActive: true, disableAfterTrigger: true, cooldownMinutes: 60, lastTriggeredAt: nil
        )
        try DatabaseManager.shared.insert(&condition)
        XCTAssertNotNil(condition.id, "삽입 후 id가 할당돼야 함")

        let now = Date()
        var updated = condition
        updated.isActive = false
        updated.lastTriggeredAt = now

        var history = AlertHistory(
            id: nil, symbol: sym, triggerType: .targetPrice,
            message: "목표가 도달 테스트", triggeredAt: now
        )
        try DatabaseManager.shared.recordAlertFired(history: &history, condition: updated)

        XCTAssertNotNil(history.id, "recordAlertFired 후 history.id가 할당돼야 함")

        guard let savedCond = try DatabaseManager.shared.fetchAlertConditions()
            .first(where: { $0.id == condition.id }) else {
            XCTFail("업데이트된 조건을 찾을 수 없음"); return
        }
        XCTAssertFalse(savedCond.isActive,
                       "disableAfterTrigger = true 이면 발화 후 isActive = false")
        XCTAssertNotNil(savedCond.lastTriggeredAt, "발화 후 lastTriggeredAt이 설정돼야 함")
    }

    // MARK: - AlertCondition: update 반영

    @MainActor func test_updateAlertCondition_persistsChange() throws {
        let sym = prefix + "COND02"
        var condition = AlertCondition(
            id: nil, symbol: sym, triggerType: .stopLoss, threshold: 50_000,
            isActive: true, disableAfterTrigger: false, cooldownMinutes: 30, lastTriggeredAt: nil
        )
        try DatabaseManager.shared.insert(&condition)

        var toggled = condition
        toggled.isActive = false
        try DatabaseManager.shared.update(toggled)

        let fetched = try DatabaseManager.shared.fetchAlertConditions().first { $0.id == condition.id }
        XCTAssertEqual(fetched?.isActive, false)
    }
}

// MARK: - 클린업 헬퍼 (self 캡처 없이 사용하기 위해 전역 함수로 정의)

@MainActor
private func cleanup(prefix: String, accountIds: [String]) {
    let db = DatabaseManager.shared
    let watchItems = (try? db.fetchWatchlist()) ?? []
    for item in watchItems where item.symbol.hasPrefix(prefix) {
        try? db.delete(item)
    }
    for accountId in accountIds {
        let portItems = (try? db.fetchPortfolio(for: accountId)) ?? []
        for item in portItems where item.symbol.hasPrefix(prefix) {
            try? db.delete(item)
        }
    }
    let conditions = (try? db.fetchAlertConditions()) ?? []
    for cond in conditions where cond.symbol.hasPrefix(prefix) {
        try? db.delete(cond)
    }
}
