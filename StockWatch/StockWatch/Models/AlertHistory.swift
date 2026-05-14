import Foundation
import GRDB

struct AlertHistory: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var symbol: String
    var triggerType: TriggerType
    var message: String
    var triggeredAt: Date
    var metadata: String?   // DART 공시: rcept_no 저장

    static let databaseTableName = "alert_history"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
