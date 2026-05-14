import Foundation
import GRDB

struct AlertCondition: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var symbol: String
    var triggerType: TriggerType
    var threshold: Double
    var isActive: Bool
    var disableAfterTrigger: Bool
    var cooldownMinutes: Int
    var lastTriggeredAt: Date?

    static let databaseTableName = "alert_conditions"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

enum TriggerType: String, Codable {
    case targetPrice = "target_price"
    case stopLoss = "stop_loss"
    case rateUp = "rate_up"
    case rateDown = "rate_down"
    case volumeSpike = "volume_spike"

    var displayName: String {
        switch self {
        case .targetPrice:  return "목표가 도달"
        case .stopLoss:     return "손절가 도달"
        case .rateUp:       return "등락률 상승"
        case .rateDown:     return "등락률 하락"
        case .volumeSpike:  return "거래량 급증"
        }
    }

    var unit: String {
        switch self {
        case .targetPrice, .stopLoss: return "원"
        case .rateUp, .rateDown:      return "%"
        case .volumeSpike:            return "배"
        }
    }
}
