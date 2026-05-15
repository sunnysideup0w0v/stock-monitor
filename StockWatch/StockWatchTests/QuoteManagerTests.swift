import XCTest
@testable import StockWatch

final class QuoteManagerTests: XCTestCase {

    private let udKey = "QuoteManager.disconnectAlert"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: udKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: udKey)
        super.tearDown()
    }

    // MARK: - disconnectAlertEnabled

    @MainActor func test_disconnectAlertEnabled_defaultIsTrue() {
        // object(forKey:)가 nil → 기본값 true 반환
        UserDefaults.standard.removeObject(forKey: udKey)
        XCTAssertTrue(QuoteManager.disconnectAlertEnabled)
    }

    @MainActor func test_disconnectAlertEnabled_persistsToUserDefaults() {
        QuoteManager.disconnectAlertEnabled = false
        XCTAssertFalse(QuoteManager.disconnectAlertEnabled)
        XCTAssertEqual(UserDefaults.standard.object(forKey: udKey) as? Bool, false)

        QuoteManager.disconnectAlertEnabled = true
        XCTAssertTrue(QuoteManager.disconnectAlertEnabled)
    }

    // MARK: - reconnect

    @MainActor func test_reconnect_doesNothingWhenNoSymbols() {
        // currentSymbols가 빈 상태에서 reconnect → connectionState 변화 없음
        QuoteManager.shared.setAdapter(MockBrokerAdapter())
        // startPolling(symbols: []) → currentSymbols = []
        QuoteManager.shared.startPolling(symbols: [])

        let stateBefore = QuoteManager.shared.connectionState
        QuoteManager.shared.reconnect()

        XCTAssertEqual(QuoteManager.shared.connectionState, stateBefore)
    }

    @MainActor func test_reconnect_updatesCurrentSymbolsOnStartPolling() {
        QuoteManager.shared.setAdapter(MockBrokerAdapter())
        QuoteManager.shared.startPolling(symbols: ["005930", "000660"])
        XCTAssertEqual(QuoteManager.shared.currentSymbols, ["005930", "000660"])

        // reconnect 후에도 currentSymbols 유지
        QuoteManager.shared.reconnect()
        XCTAssertEqual(QuoteManager.shared.currentSymbols, ["005930", "000660"])

        // 정리
        QuoteManager.shared.stopPolling()
    }
}
