import Foundation
import GRDB

struct PortfolioItem: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var symbol: String
    var name: String
    var averagePrice: Int
    var quantity: Int

    static let databaseTableName = "portfolio"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var totalCost: Int { averagePrice * quantity }

    func evaluatedGain(currentPrice: Int) -> Int {
        (currentPrice - averagePrice) * quantity
    }

    func gainRate(currentPrice: Int) -> Double {
        guard averagePrice > 0 else { return 0 }
        return Double(currentPrice - averagePrice) / Double(averagePrice) * 100
    }
}
