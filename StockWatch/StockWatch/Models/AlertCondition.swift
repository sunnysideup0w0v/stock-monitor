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

enum TriggerType: String, Codable, CaseIterable {
    case targetPrice       = "target_price"
    case stopLoss          = "stop_loss"
    case rateUp            = "rate_up"
    case rateDown          = "rate_down"
    case volumeSpike       = "volume_spike"
    case portfolioGain     = "portfolio_gain"      // 전체 평가손익 >= N원
    case portfolioLoss     = "portfolio_loss"      // 전체 평가손익 <= -N원
    case portfolioGainRate = "portfolio_gain_rate" // 전체 수익률 >= N%
    case portfolioLossRate = "portfolio_loss_rate" // 전체 수익률 <= -N%
    case dartDisclosure    = "dart_disclosure"     // DART 공시 (사용자가 직접 설정 불가)

    var displayName: String {
        switch self {
        case .targetPrice:       return "목표가 도달"
        case .stopLoss:          return "손절가 도달"
        case .rateUp:            return "등락률 상승"
        case .rateDown:          return "등락률 하락"
        case .volumeSpike:       return "거래량 급증"
        case .portfolioGain:     return "포트폴리오 목표손익"
        case .portfolioLoss:     return "포트폴리오 손절손익"
        case .portfolioGainRate: return "포트폴리오 목표수익률"
        case .portfolioLossRate: return "포트폴리오 손절수익률"
        case .dartDisclosure:    return "DART 공시"
        }
    }

    var unit: String {
        switch self {
        case .targetPrice, .stopLoss:                return "원"
        case .rateUp, .rateDown:                     return "%"
        case .volumeSpike:                           return "배"
        case .portfolioGain, .portfolioLoss:         return "원"
        case .portfolioGainRate, .portfolioLossRate: return "%"
        case .dartDisclosure:                        return ""
        }
    }

    var isPortfolioLevel: Bool {
        switch self {
        case .portfolioGain, .portfolioLoss, .portfolioGainRate, .portfolioLossRate: return true
        default: return false
        }
    }

    // 알림 설정 UI의 조건 추가 폼에 표시할 유형 목록 (DART 공시는 DARTManager가 자동 생성)
    static var userConfigurable: [TriggerType] {
        [.targetPrice, .stopLoss, .rateUp, .rateDown, .volumeSpike,
         .portfolioGain, .portfolioLoss, .portfolioGainRate, .portfolioLossRate]
    }
}
