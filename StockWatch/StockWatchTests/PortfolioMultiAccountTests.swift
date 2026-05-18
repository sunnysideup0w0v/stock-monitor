import XCTest
@testable import StockWatch

/// 포트폴리오 다중 계좌 격리 및 연결 상태 필터 동작 검증.
/// 브로커별 accountId가 다른 항목이 서로 노출되지 않아야 한다.
final class PortfolioMultiAccountTests: XCTestCase {

    private let prefix   = "ZPORT_"
    private let accountA = "TEST-PORT-KIS-AAAA"
    private let accountB = "TEST-PORT-KWOOM-BBB"

    override func setUp() async throws {
        try await super.setUp()
        AccountManager.testAccountId = accountA
        let pfx = prefix
        let acctA = accountA
        let acctB = accountB
        await MainActor.run { cleanupPortfolio(prefix: pfx, accountIds: [acctA, acctB]) }
    }

    override func tearDown() async throws {
        let pfx = prefix
        let acctA = accountA
        let acctB = accountB
        await MainActor.run { cleanupPortfolio(prefix: pfx, accountIds: [acctA, acctB]) }
        AccountManager.testAccountId = nil
        try await super.tearDown()
    }

    // MARK: - insert가 currentAccountId를 사용하는지

    @MainActor func test_insert_setsAccountIdFromCurrentAccount() throws {
        AccountManager.testAccountId = accountA
        var item = PortfolioItem(id: nil, symbol: prefix + "P1", name: "A계정종목",
                                 averagePrice: 50_000, quantity: 10)
        try DatabaseManager.shared.insert(&item)
        XCTAssertEqual(item.accountId, accountA)
    }

    // MARK: - 브로커 격리

    @MainActor func test_fetchPortfolioFor_isolatesBrokerItems() throws {
        AccountManager.testAccountId = accountA
        var itemA = PortfolioItem(id: nil, symbol: prefix + "P2", name: "A종목",
                                  averagePrice: 10_000, quantity: 1)
        try DatabaseManager.shared.insert(&itemA)

        AccountManager.testAccountId = accountB
        var itemB = PortfolioItem(id: nil, symbol: prefix + "P3", name: "B종목",
                                  averagePrice: 20_000, quantity: 2)
        try DatabaseManager.shared.insert(&itemB)

        let forA = try DatabaseManager.shared.fetchPortfolio(for: accountA)
        XCTAssertTrue(forA.contains(where: { $0.symbol == prefix + "P2" }))
        XCTAssertFalse(forA.contains(where: { $0.symbol == prefix + "P3" }),
                       "A계좌 조회에 B계좌 항목이 포함되면 안 됨")

        let forB = try DatabaseManager.shared.fetchPortfolio(for: accountB)
        XCTAssertTrue(forB.contains(where: { $0.symbol == prefix + "P3" }))
        XCTAssertFalse(forB.contains(where: { $0.symbol == prefix + "P2" }),
                       "B계좌 조회에 A계좌 항목이 포함되면 안 됨")
    }

    // MARK: - fetchPortfolio (connected IDs 기반)

    @MainActor func test_fetchPortfolio_returnsOnlyConnectedBrokerItems() throws {
        // A 항목 삽입
        AccountManager.testAccountId = accountA
        var itemA = PortfolioItem(id: nil, symbol: prefix + "P4", name: "A연결",
                                  averagePrice: 30_000, quantity: 5)
        try DatabaseManager.shared.insert(&itemA)

        // B 항목 삽입
        AccountManager.testAccountId = accountB
        var itemB = PortfolioItem(id: nil, symbol: prefix + "P5", name: "B비연결",
                                  averagePrice: 40_000, quantity: 3)
        try DatabaseManager.shared.insert(&itemB)

        // A 계좌만 연결 상태
        AccountManager.testAccountId = accountA
        let result = try DatabaseManager.shared.fetchPortfolio()
        XCTAssertTrue(result.contains(where: { $0.symbol == prefix + "P4" }))
        XCTAssertFalse(result.contains(where: { $0.symbol == prefix + "P5" }),
                       "미연결 B 계좌 항목은 fetchPortfolio()에 포함되면 안 됨")
    }

    @MainActor func test_fetchPortfolio_emptyWhenNoConnectedAccounts() throws {
        AccountManager.testAccountId = nil
        defer { AccountManager.testAccountId = accountA }

        // CI 환경(Keychain 비어있음)에서만 확인
        if AccountManager.connectedAccountIds.isEmpty {
            let result = try DatabaseManager.shared.fetchPortfolio()
            XCTAssertTrue(result.isEmpty, "미연결 시 fetchPortfolio()는 빈 배열 반환")
        }
    }

    // MARK: - showInPopover 기본값

    @MainActor func test_insert_showInPopover_defaultFalse() throws {
        AccountManager.testAccountId = accountA
        var item = PortfolioItem(id: nil, symbol: prefix + "P6", name: "팝오버테스트",
                                  averagePrice: 100_000, quantity: 1)
        try DatabaseManager.shared.insert(&item)
        let fetched = try DatabaseManager.shared.fetchPortfolio(for: accountA)
                                                .first { $0.symbol == prefix + "P6" }
        XCTAssertEqual(fetched?.showInPopover, false, "showInPopover 기본값은 false여야 함")
    }

    // MARK: - update 반영

    @MainActor func test_update_showInPopover_persists() throws {
        AccountManager.testAccountId = accountA
        var item = PortfolioItem(id: nil, symbol: prefix + "P7", name: "팝오버업데이트",
                                  averagePrice: 50_000, quantity: 2)
        try DatabaseManager.shared.insert(&item)

        var updated = item
        updated.showInPopover = true
        try DatabaseManager.shared.update(updated)

        let fetched = try DatabaseManager.shared.fetchPortfolio(for: accountA)
                                                .first { $0.symbol == prefix + "P7" }
        XCTAssertEqual(fetched?.showInPopover, true)
    }

    // MARK: - 산술 계산 불변량

    @MainActor func test_portfolioItem_totalCost() throws {
        AccountManager.testAccountId = accountA
        let item = PortfolioItem(id: nil, symbol: prefix + "P8", name: "수익계산",
                                  averagePrice: 50_000, quantity: 10)
        XCTAssertEqual(item.totalCost, 500_000, "totalCost = averagePrice × quantity")
    }

    @MainActor func test_portfolioItem_gainRate_withCurrentPrice() throws {
        let item = PortfolioItem(id: nil, symbol: prefix + "P9", name: "수익률",
                                  averagePrice: 100_000, quantity: 5)
        let gain = item.evaluatedGain(currentPrice: 110_000)
        XCTAssertEqual(gain, 50_000, "평가손익 = (현재가 - 평균단가) × 수량")
        let rate = item.gainRate(currentPrice: 110_000)
        XCTAssertEqual(rate, 10.0, accuracy: 0.001)
    }
}

@MainActor
private func cleanupPortfolio(prefix: String, accountIds: [String]) {
    for accountId in accountIds {
        let items = (try? DatabaseManager.shared.fetchPortfolio(for: accountId)) ?? []
        for item in items where item.symbol.hasPrefix(prefix) {
            try? DatabaseManager.shared.delete(item)
        }
    }
}
