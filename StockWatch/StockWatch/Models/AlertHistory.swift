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
    var isHidden: Bool      // true이면 화면에서 숨김 (DB에는 보존)

    init(id: Int64? = nil, symbol: String, stockName: String? = nil,
         triggerType: TriggerType, message: String, triggeredAt: Date,
         metadata: String? = nil, isHidden: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.stockName = stockName
        self.triggerType = triggerType
        self.message = message
        self.triggeredAt = triggeredAt
        self.metadata = metadata
        self.isHidden = isHidden
    }

    static let databaseTableName = "alert_history"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
