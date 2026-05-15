import XCTest
@testable import StockWatch

final class AlertEvaluatorTests: XCTestCase {

    // MARK: - canFire

    @MainActor func test_canFire_noLastTriggered_returnsTrue() {
        var condition = makeCondition(triggerType: .targetPrice, threshold: 70000)
        condition.lastTriggeredAt = nil
        XCTAssertTrue(AlertEvaluator.shared.canFire(condition: condition, now: Date()))
    }

    @MainActor func test_canFire_cooldownNotElapsed_returnsFalse() {
        var condition = makeCondition(triggerType: .targetPrice, threshold: 70000)
        condition.cooldownMinutes = 60
        condition.lastTriggeredAt = Date().addingTimeInterval(-1800) // 30분 전
        XCTAssertFalse(AlertEvaluator.shared.canFire(condition: condition, now: Date()))
    }

    @MainActor func test_canFire_cooldownElapsed_returnsTrue() {
        var condition = makeCondition(triggerType: .targetPrice, threshold: 70000)
        condition.cooldownMinutes = 30
        condition.lastTriggeredAt = Date().addingTimeInterval(-3601) // 61분 전
        XCTAssertTrue(AlertEvaluator.shared.canFire(condition: condition, now: Date()))
    }

    // MARK: - isTriggered: targetPrice

    @MainActor func test_targetPrice_priceAboveThreshold_triggers() {
        let condition = makeCondition(triggerType: .targetPrice, threshold: 70000)
        let quote = makeQuote(price: 71000)
        XCTAssertTrue(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    @MainActor func test_targetPrice_priceEqualThreshold_triggers() {
        let condition = makeCondition(triggerType: .targetPrice, threshold: 70000)
        let quote = makeQuote(price: 70000)
        XCTAssertTrue(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    @MainActor func test_targetPrice_priceBelowThreshold_doesNotTrigger() {
        let condition = makeCondition(triggerType: .targetPrice, threshold: 70000)
        let quote = makeQuote(price: 69000)
        XCTAssertFalse(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    // MARK: - isTriggered: stopLoss

    @MainActor func test_stopLoss_priceBelowThreshold_triggers() {
        let condition = makeCondition(triggerType: .stopLoss, threshold: 60000)
        let quote = makeQuote(price: 59000)
        XCTAssertTrue(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    @MainActor func test_stopLoss_priceAboveThreshold_doesNotTrigger() {
        let condition = makeCondition(triggerType: .stopLoss, threshold: 60000)
        let quote = makeQuote(price: 61000)
        XCTAssertFalse(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    // MARK: - isTriggered: rateUp / rateDown

    @MainActor func test_rateUp_rateAboveThreshold_triggers() {
        let condition = makeCondition(triggerType: .rateUp, threshold: 3.0)
        let quote = makeQuote(price: 70000, changeRate: 3.5)
        XCTAssertTrue(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    @MainActor func test_rateUp_rateBelowThreshold_doesNotTrigger() {
        let condition = makeCondition(triggerType: .rateUp, threshold: 3.0)
        let quote = makeQuote(price: 70000, changeRate: 2.5)
        XCTAssertFalse(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    @MainActor func test_rateDown_rateBelowNegativeThreshold_triggers() {
        let condition = makeCondition(triggerType: .rateDown, threshold: 3.0)
        let quote = makeQuote(price: 70000, changeRate: -3.5)
        XCTAssertTrue(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    @MainActor func test_rateDown_rateAboveNegativeThreshold_doesNotTrigger() {
        let condition = makeCondition(triggerType: .rateDown, threshold: 3.0)
        let quote = makeQuote(price: 70000, changeRate: -2.5)
        XCTAssertFalse(AlertEvaluator.shared.isTriggered(quote: quote, condition: condition))
    }

    // MARK: - isWithinMarketHours

    func test_marketHours_weekday_0900_isWithin() {
        XCTAssertTrue(isWithinMarketHours(weekday: 2, hour: 9, minute: 0))
    }

    func test_marketHours_weekday_1530_isWithin() {
        XCTAssertTrue(isWithinMarketHours(weekday: 2, hour: 15, minute: 30))
    }

    func test_marketHours_weekday_1531_isOutside() {
        XCTAssertFalse(isWithinMarketHours(weekday: 2, hour: 15, minute: 31))
    }

    func test_marketHours_weekday_0859_isOutside() {
        XCTAssertFalse(isWithinMarketHours(weekday: 2, hour: 8, minute: 59))
    }

    func test_marketHours_saturday_isOutside() {
        XCTAssertFalse(isWithinMarketHours(weekday: 7, hour: 10, minute: 0))
    }

    func test_marketHours_sunday_isOutside() {
        XCTAssertFalse(isWithinMarketHours(weekday: 1, hour: 10, minute: 0))
    }

    // MARK: - Helpers

    private func makeCondition(triggerType: TriggerType, threshold: Double) -> AlertCondition {
        AlertCondition(
            id: nil,
            symbol: "005930",
            triggerType: triggerType,
            threshold: threshold,
            isActive: true,
            disableAfterTrigger: false,
            cooldownMinutes: 60,
            lastTriggeredAt: nil
        )
    }

    private func makeQuote(price: Int, changeRate: Double = 0) -> StockQuote {
        StockQuote(
            symbol: "005930",
            name: "삼성전자",
            price: price,
            changeAmount: 0,
            changeRate: changeRate,
            volume: 1_000_000,
            timestamp: Date()
        )
    }

    private func isWithinMarketHours(weekday: Int, hour: Int, minute: Int) -> Bool {
        guard weekday >= 2 && weekday <= 6 else { return false }
        let minutes = hour * 60 + minute
        return minutes >= 9 * 60 && minutes <= 15 * 60 + 30
    }
}
