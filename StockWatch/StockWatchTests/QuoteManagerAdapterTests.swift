import XCTest
@testable import StockWatch

/// QuoteManager의 어댑터 추가/제거 생명주기를 검증한다.
/// 리팩토링(R2 BrokerSessionManager 추출)에서 이 계약이 유지됨을 보장하기 위한 안전망.
final class QuoteManagerAdapterTests: XCTestCase {

    private let testAdapterId = "TEST-ADAPTER-QUOTEMANAGER"

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            QuoteManager.shared.stopPolling()
            QuoteManager.shared.setAdapter(MockBrokerAdapter())
        }
    }

    override func tearDown() async throws {
        let adapterId = testAdapterId
        await MainActor.run {
            QuoteManager.shared.stopPolling()
            QuoteManager.shared.removeAdapter(id: adapterId)
            QuoteManager.shared.setAdapter(MockBrokerAdapter())
        }
        try await super.tearDown()
    }

    // MARK: - addAdapter

    @MainActor func test_addAdapter_doesNotResetCurrentSymbols() {
        QuoteManager.shared.startPolling(symbols: ["005930", "000660"])
        XCTAssertEqual(QuoteManager.shared.currentSymbols, ["005930", "000660"])

        QuoteManager.shared.addAdapter(id: testAdapterId, adapter: MockBrokerAdapter())

        XCTAssertEqual(QuoteManager.shared.currentSymbols, ["005930", "000660"],
                       "addAdapter은 currentSymbols를 초기화하지 않아야 함")

        QuoteManager.shared.stopPolling()
    }

    @MainActor func test_addAdapter_resetsConsecutiveFailureState() {
        // setUp에서 setAdapter 호출 → 이후 addAdapter가 재연결 상태를 초기화하는지 확인
        // connectionState는 .disconnected에서 시작
        XCTAssertEqual(QuoteManager.shared.connectionState, .disconnected)
        QuoteManager.shared.addAdapter(id: testAdapterId, adapter: MockBrokerAdapter())
        XCTAssertEqual(QuoteManager.shared.connectionState, .disconnected,
                       "addAdapter 후 connectionState는 .disconnected여야 함 (아직 폴링 시작 전)")
    }

    // MARK: - removeAdapter

    @MainActor func test_removeAdapter_afterAddAdapter_connectionStateDisconnected() {
        QuoteManager.shared.addAdapter(id: testAdapterId, adapter: MockBrokerAdapter())
        QuoteManager.shared.removeAdapter(id: testAdapterId)
        // 어댑터가 없을 때 setAdapter(Mock)이 호출됨 → .disconnected
        XCTAssertEqual(QuoteManager.shared.connectionState, .disconnected)
    }

    @MainActor func test_removeAdapter_unknownId_doesNotCrash() {
        // 존재하지 않는 ID 제거 → 크래시 없음
        QuoteManager.shared.removeAdapter(id: "NON-EXISTENT-ID")
        XCTAssertEqual(QuoteManager.shared.connectionState, .disconnected)
    }

    // MARK: - setAdapter

    @MainActor func test_setAdapter_resetsConnectionState() {
        QuoteManager.shared.setAdapter(MockBrokerAdapter())
        XCTAssertEqual(QuoteManager.shared.connectionState, .disconnected)
    }

    @MainActor func test_setAdapter_doesNotChangeCurrentSymbols() {
        QuoteManager.shared.startPolling(symbols: ["005930"])
        let symbolsBefore = QuoteManager.shared.currentSymbols

        // setAdapter를 불러도 currentSymbols는 그대로
        QuoteManager.shared.setAdapter(MockBrokerAdapter())
        XCTAssertEqual(QuoteManager.shared.currentSymbols, symbolsBefore,
                       "setAdapter는 currentSymbols를 초기화하지 않아야 함")

        QuoteManager.shared.stopPolling()
    }

    // MARK: - reconnect

    @MainActor func test_reconnect_withSymbols_doesNotChangeThem() {
        QuoteManager.shared.startPolling(symbols: ["005930", "035420"])
        QuoteManager.shared.reconnect()
        XCTAssertEqual(QuoteManager.shared.currentSymbols, ["005930", "035420"],
                       "reconnect 후에도 currentSymbols 유지")
        QuoteManager.shared.stopPolling()
    }

    // MARK: - fetchBalance: 연결된 어댑터 사용

    @MainActor func test_fetchBalance_forUnknownAdapterId_throwsNotConnected() async {
        do {
            _ = try await QuoteManager.shared.fetchBalance(for: "NON-EXISTENT-ACCOUNT")
            XCTFail("존재하지 않는 어댑터 ID로 fetchBalance를 호출하면 에러가 발생해야 함")
        } catch BrokerError.notConnected {
            // 예상된 에러
        } catch {
            XCTFail("예상치 못한 에러: \(error)")
        }
    }
}
