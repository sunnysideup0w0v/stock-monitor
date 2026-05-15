import XCTest
@testable import StockWatch

final class PortfolioItemTests: XCTestCase {

    // MARK: - totalCost

    func test_totalCost_basic() {
        let item = makeItem(averagePrice: 70000, quantity: 10)
        XCTAssertEqual(item.totalCost, 700_000)
    }

    func test_totalCost_singleShare() {
        let item = makeItem(averagePrice: 50000, quantity: 1)
        XCTAssertEqual(item.totalCost, 50000)
    }

    // MARK: - evaluatedGain

    func test_evaluatedGain_profit() {
        let item = makeItem(averagePrice: 60000, quantity: 10)
        XCTAssertEqual(item.evaluatedGain(currentPrice: 70000), 100_000)
    }

    func test_evaluatedGain_loss() {
        let item = makeItem(averagePrice: 70000, quantity: 10)
        XCTAssertEqual(item.evaluatedGain(currentPrice: 60000), -100_000)
    }

    func test_evaluatedGain_breakEven() {
        let item = makeItem(averagePrice: 70000, quantity: 10)
        XCTAssertEqual(item.evaluatedGain(currentPrice: 70000), 0)
    }

    // MARK: - gainRate

    func test_gainRate_profit() {
        let item = makeItem(averagePrice: 80000, quantity: 10)
        let rate = item.gainRate(currentPrice: 100000)
        XCTAssertEqual(rate, 25.0, accuracy: 0.001)
    }

    func test_gainRate_loss() {
        let item = makeItem(averagePrice: 100000, quantity: 10)
        let rate = item.gainRate(currentPrice: 80000)
        XCTAssertEqual(rate, -20.0, accuracy: 0.001)
    }

    func test_gainRate_zeroAveragePrice_returnsZero() {
        let item = makeItem(averagePrice: 0, quantity: 10)
        XCTAssertEqual(item.gainRate(currentPrice: 70000), 0)
    }

    // MARK: - Helpers

    private func makeItem(averagePrice: Int, quantity: Int) -> PortfolioItem {
        PortfolioItem(
            id: nil,
            symbol: "005930",
            name: "삼성전자",
            averagePrice: averagePrice,
            quantity: quantity
        )
    }
}
