import Foundation

struct StockQuote: Sendable, Equatable {
    let symbol: String
    let name: String
    let price: Int
    let changeAmount: Int
    let changeRate: Double
    let volume: Int
    let timestamp: Date

    var isUp: Bool { changeAmount >= 0 }

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: price)) ?? "\(price)") + "원"
    }

    var formattedChange: String {
        let sign = changeRate >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, changeRate)
    }
}
