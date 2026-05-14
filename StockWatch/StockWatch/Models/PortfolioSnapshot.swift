import Foundation
import GRDB

struct PortfolioSnapshot: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var timestamp: Date
    var totalValue: Int    // 총 평가금액
    var totalGain: Int     // 총 평가손익
    var gainPct: Double    // 수익률 %

    static let databaseTableName = "portfolio_snapshots"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
