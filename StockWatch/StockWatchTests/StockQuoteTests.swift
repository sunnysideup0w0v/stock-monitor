import XCTest
@testable import StockWatch

final class StockQuoteTests: XCTestCase {

    // MARK: - formattedPrice

    func test_formattedPrice_includesWon() {
        let quote = makeQuote(price: 70000)
        XCTAssertTrue(quote.formattedPrice.hasSuffix("원"))
    }

    func test_formattedPrice_largeNumber_hasCommas() {
        let quote = makeQuote(price: 1_000_000)
        XCTAssertTrue(quote.formattedPrice.contains(","))
    }

    func test_formattedPrice_smallNumber_noComma() {
        let quote = makeQuote(price: 999)
        XCTAssertFalse(quote.formattedPrice.dropLast(1).contains(",")) // drop "원"
    }

    // MARK: - formattedChange

    func test_formattedChange_positive_hasPlusSign() {
        let quote = makeQuote(price: 70000, changeRate: 1.5)
        XCTAssertTrue(quote.formattedChange.hasPrefix("+"))
    }

    func test_formattedChange_negative_hasMinusSign() {
        let quote = makeQuote(price: 70000, changeRate: -1.5)
        XCTAssertTrue(quote.formattedChange.hasPrefix("-"))
    }

    func test_formattedChange_zero_hasPlusSign() {
        let quote = makeQuote(price: 70000, changeRate: 0)
        XCTAssertTrue(quote.formattedChange.hasPrefix("+"))
    }

    func test_formattedChange_containsPercent() {
        let quote = makeQuote(price: 70000, changeRate: 2.5)
        XCTAssertTrue(quote.formattedChange.contains("%"))
    }

    // MARK: - isUp

    func test_isUp_positiveChange_true() {
        let quote = makeQuote(price: 70000, changeAmount: 100)
        XCTAssertTrue(quote.isUp)
    }

    func test_isUp_zeroChange_true() {
        let quote = makeQuote(price: 70000, changeAmount: 0)
        XCTAssertTrue(quote.isUp)
    }

    func test_isUp_negativeChange_false() {
        let quote = makeQuote(price: 70000, changeAmount: -100)
        XCTAssertFalse(quote.isUp)
    }

    // MARK: - Helpers

    private func makeQuote(price: Int, changeAmount: Int = 0, changeRate: Double = 0) -> StockQuote {
        StockQuote(
            symbol: "005930",
            name: "삼성전자",
            price: price,
            changeAmount: changeAmount,
            changeRate: changeRate,
            volume: 1_000_000,
            timestamp: Date()
        )
    }
}
