import Foundation
import GRDB

struct AlertHistory: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var symbol: String
    var stockName: String?  // 발화 시점 종목명 스냅샷 (nil이면 구형 레코드)
    var triggerType: TriggerType
    var message: String
    var triggeredAt: Date
    var metadata: String?   // DART 공시: rcept_no 저장

    static let databaseTableName = "alert_history"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
