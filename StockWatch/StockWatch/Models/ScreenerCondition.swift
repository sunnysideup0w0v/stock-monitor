import Foundation

struct ScreenerCondition: Codable, Identifiable {
    var id: UUID = UUID()
    var type: ConditionType
    var isEnabled: Bool = true
    var minValue: Double?
    var maxValue: Double?
    var stringValue: String?

    enum ConditionType: String, Codable, CaseIterable {
        case priceRange
        case volumeMin
        case changeRateRange
        case perRange
        case pbrRange
        case marketCapRange
        case sectorFilter
        case marketFilter
        case instrumentType

        var displayName: String {
            switch self {
            case .priceRange:      return "현재가 (원)"
            case .volumeMin:       return "최소 거래량"
            case .changeRateRange: return "등락률 (%)"
            case .perRange:        return "PER (배)"
            case .pbrRange:        return "PBR (배)"
            case .marketCapRange:  return "시가총액 (억원)"
            case .sectorFilter:    return "업종"
            case .marketFilter:    return "시장 구분"
            case .instrumentType:  return "종목 유형"
            }
        }

        var shortName: String {
            switch self {
            case .priceRange:      return "현재가"
            case .volumeMin:       return "거래량"
            case .changeRateRange: return "등락률"
            case .perRange:        return "PER"
            case .pbrRange:        return "PBR"
            case .marketCapRange:  return "시가총액"
            case .sectorFilter:    return "업종"
            case .marketFilter:    return "시장"
            case .instrumentType:  return "종목유형"
            }
        }

        var usesStringValue: Bool {
            self == .sectorFilter || self == .marketFilter || self == .instrumentType
        }

        var supportsMin: Bool {
            switch self {
            case .sectorFilter, .marketFilter, .instrumentType: return false
            default: return true
            }
        }

        var supportsMax: Bool {
            switch self {
            case .volumeMin, .sectorFilter, .marketFilter, .instrumentType: return false
            default: return true
            }
        }

        var unit: String {
            switch self {
            case .priceRange:      return "원"
            case .volumeMin:       return "주"
            case .changeRateRange: return "%"
            case .perRange:        return "배"
            case .pbrRange:        return "배"
            case .marketCapRange:  return "억원"
            default: return ""
            }
        }

        var minPlaceholder: String {
            switch self {
            case .priceRange:      return "예: 10000"
            case .volumeMin:       return "예: 100000"
            case .changeRateRange: return "예: -5"
            case .perRange:        return "예: 0"
            case .pbrRange:        return "예: 0"
            case .marketCapRange:  return "예: 1000"
            default: return ""
            }
        }

        var maxPlaceholder: String {
            switch self {
            case .priceRange:      return "예: 100000"
            case .changeRateRange: return "예: 5"
            case .perRange:        return "예: 15"
            case .pbrRange:        return "예: 1"
            case .marketCapRange:  return "예: 50000"
            default: return ""
            }
        }
    }
}
