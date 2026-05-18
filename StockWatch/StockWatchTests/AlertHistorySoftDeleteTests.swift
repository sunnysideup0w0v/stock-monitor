import XCTest
@testable import StockWatch

/// AlertHistory soft-delete (isHidden 플래그) 동작 검증.
/// DB에는 보존하면서 fetch 결과에서는 숨기는 패턴이 올바르게 동작하는지 확인한다.
final class AlertHistorySoftDeleteTests: XCTestCase {

    private let prefix = "ZHIDE_"

    override func setUp() async throws {
        try await super.setUp()
        let pfx = prefix
        await MainActor.run { cleanupHistory(prefix: pfx) }
    }

    override func tearDown() async throws {
        let pfx = prefix
        await MainActor.run { cleanupHistory(prefix: pfx) }
        try await super.tearDown()
    }

    // MARK: - 기본 삽입

    @MainActor func test_insertAlertHistory_defaultIsHiddenFalse() throws {
        var h = makeHistory(symbol: prefix + "A1")
        try DatabaseManager.shared.insert(&h)
        XCTAssertNotNil(h.id, "삽입 후 id 할당")
        XCTAssertFalse(h.isHidden, "기본 isHidden은 false")
    }

    @MainActor func test_insertAlertHistory_nilMetadata_succeeds() throws {
        var h = makeHistory(symbol: prefix + "A2", metadata: nil)
        XCTAssertNoThrow(try DatabaseManager.shared.insert(&h))
        XCTAssertNotNil(h.id)
    }

    @MainActor func test_insertAlertHistory_nilStockName_succeeds() throws {
        var h = makeHistory(symbol: prefix + "A3", stockName: nil)
        XCTAssertNoThrow(try DatabaseManager.shared.insert(&h))
        XCTAssertNotNil(h.id)
    }

    @MainActor func test_insertAlertHistory_withMetadata_roundtrip() throws {
        let rcept = "20240101000001"
        var h = makeHistory(symbol: prefix + "A4", metadata: rcept)
        try DatabaseManager.shared.insert(&h)

        let history = try DatabaseManager.shared.fetchAlertHistory(limit: 1000)
        let found = history.first { $0.symbol == prefix + "A4" }
        XCTAssertEqual(found?.metadata, rcept)
    }

    // MARK: - 단건 숨기기

    @MainActor func test_hideAlertHistory_removesFromFetch() throws {
        var h = makeHistory(symbol: prefix + "B1")
        try DatabaseManager.shared.insert(&h)
        let id = try XCTUnwrap(h.id)

        // 숨기기 전 — 조회됨
        let before = try DatabaseManager.shared.fetchAlertHistory(limit: 1000)
        XCTAssertTrue(before.contains(where: { $0.id == id }))

        try DatabaseManager.shared.hideAlertHistory(id: id)

        // 숨긴 후 — 조회 안 됨
        let after = try DatabaseManager.shared.fetchAlertHistory(limit: 1000)
        XCTAssertFalse(after.contains(where: { $0.id == id }),
                       "hideAlertHistory 후 해당 항목은 fetch에서 제외돼야 함")
    }

    @MainActor func test_hideAlertHistory_onlyHidesTargetItem() throws {
        var h1 = makeHistory(symbol: prefix + "B2")
        var h2 = makeHistory(symbol: prefix + "B3")
        try DatabaseManager.shared.insert(&h1)
        try DatabaseManager.shared.insert(&h2)
        let id1 = try XCTUnwrap(h1.id)
        let id2 = try XCTUnwrap(h2.id)

        try DatabaseManager.shared.hideAlertHistory(id: id1)

        let after = try DatabaseManager.shared.fetchAlertHistory(limit: 1000)
        XCTAssertFalse(after.contains(where: { $0.id == id1 }), "숨긴 항목은 보이지 않아야 함")
        XCTAssertTrue(after.contains(where: { $0.id == id2 }), "다른 항목은 여전히 보여야 함")
    }

    // MARK: - 전체 숨기기

    @MainActor func test_hideAllAlertHistory_removesAllVisible() throws {
        var h1 = makeHistory(symbol: prefix + "C1")
        var h2 = makeHistory(symbol: prefix + "C2")
        var h3 = makeHistory(symbol: prefix + "C3")
        try DatabaseManager.shared.insert(&h1)
        try DatabaseManager.shared.insert(&h2)
        try DatabaseManager.shared.insert(&h3)

        try DatabaseManager.shared.hideAllAlertHistory()

        let after = try DatabaseManager.shared.fetchAlertHistory(limit: 1000)
        let remaining = after.filter { $0.symbol.hasPrefix(prefix) }
        XCTAssertTrue(remaining.isEmpty, "hideAll 후 prefix 항목이 fetch에서 모두 사라져야 함")
    }

    @MainActor func test_hideAllAlertHistory_whenAllAlreadyHidden_isIdempotent() throws {
        var h = makeHistory(symbol: prefix + "C4")
        try DatabaseManager.shared.insert(&h)
        let id = try XCTUnwrap(h.id)

        try DatabaseManager.shared.hideAlertHistory(id: id)
        // 이미 숨겨진 상태에서 전체 숨기기 — 에러 없어야 함
        XCTAssertNoThrow(try DatabaseManager.shared.hideAllAlertHistory())
    }

    @MainActor func test_hideAllAlertHistory_doesNotAffectSubsequentInserts() throws {
        var h1 = makeHistory(symbol: prefix + "C5")
        try DatabaseManager.shared.insert(&h1)
        try DatabaseManager.shared.hideAllAlertHistory()

        // 새로 삽입한 항목은 숨겨지지 않아야 함
        var h2 = makeHistory(symbol: prefix + "C6")
        try DatabaseManager.shared.insert(&h2)

        let after = try DatabaseManager.shared.fetchAlertHistory(limit: 1000)
        XCTAssertTrue(after.contains(where: { $0.symbol == prefix + "C6" }),
                      "hideAll 이후 새 삽입 항목은 visible해야 함")
    }

    // MARK: - limit 파라미터

    @MainActor func test_fetchAlertHistory_limit_respected() throws {
        for i in 0..<5 {
            var h = makeHistory(symbol: prefix + "D\(i)")
            try DatabaseManager.shared.insert(&h)
        }
        let fetched = try DatabaseManager.shared.fetchAlertHistory(limit: 2)
        // limit 적용은 전체 이력에 대해 적용 — 2개 초과하지 않아야 함
        XCTAssertLessThanOrEqual(fetched.count, 2)
    }

    // MARK: - recordAlertFired 원자성 (history + condition 함께)

    @MainActor func test_recordAlertFired_historyNotHiddenByDefault() throws {
        let sym = prefix + "E1"
        var cond = AlertCondition(
            id: nil, symbol: sym, triggerType: .targetPrice, threshold: 50_000,
            isActive: true, disableAfterTrigger: false, cooldownMinutes: 60, lastTriggeredAt: nil
        )
        try DatabaseManager.shared.insert(&cond)

        var h = makeHistory(symbol: sym)
        try DatabaseManager.shared.recordAlertFired(history: &h, condition: cond)

        let history = try DatabaseManager.shared.fetchAlertHistory(limit: 1000)
        let found = history.first { $0.symbol == sym }
        XCTAssertNotNil(found, "recordAlertFired로 삽입된 history는 fetch에서 보여야 함")
        XCTAssertFalse(found?.isHidden ?? true, "기본 isHidden = false")

        // 정리
        try DatabaseManager.shared.delete(cond)
    }

    // MARK: - Helpers

    private func makeHistory(symbol: String,
                             stockName: String? = "테스트종목",
                             metadata: String? = nil) -> AlertHistory {
        AlertHistory(
            id: nil,
            symbol: symbol,
            stockName: stockName,
            triggerType: .targetPrice,
            message: "테스트 알림",
            triggeredAt: Date(),
            metadata: metadata,
            isHidden: false
        )
    }
}

@MainActor
private func cleanupHistory(prefix: String) {
    guard let history = try? DatabaseManager.shared.fetchAlertHistory(limit: 10_000) else { return }
    for h in history where h.symbol.hasPrefix(prefix) {
        guard let id = h.id else { continue }
        try? DatabaseManager.shared.hideAlertHistory(id: id)
    }
}
