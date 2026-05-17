import Foundation
import GRDB

struct StockUniverseItem: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var symbol: String
    var name: String
    var market: String      // "KOSPI" | "KOSDAQ"
    var sector: String?
    var close: Int
    var open: Int
    var high: Int
    var low: Int
    var volume: Int
    var marketCap: Int      // 백만원 단위
    var per: Double?
    var pbr: Double?
    var isEtf: Bool
    var updatedAt: Date

    static let databaseTableName = "stock_universe"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
