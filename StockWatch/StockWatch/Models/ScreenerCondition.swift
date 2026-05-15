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
            }
        }

        var usesStringValue: Bool {
            self == .sectorFilter || self == .marketFilter
        }

        var supportsMin: Bool {
            switch self {
            case .sectorFilter, .marketFilter: return false
            default: return true
            }
        }

        var supportsMax: Bool {
            switch self {
            case .volumeMin, .sectorFilter, .marketFilter: return false
            default: return true
            }
        }

        var minPlaceholder: String {
            switch self {
            case .priceRange:      return "최소 가격"
            case .volumeMin:       return "최소 거래량"
            case .changeRateRange: return "최소 등락률"
            case .perRange:        return "최소 PER"
            case .pbrRange:        return "최소 PBR"
            case .marketCapRange:  return "최소 시가총액 (억)"
            default: return ""
            }
        }

        var maxPlaceholder: String {
            switch self {
            case .priceRange:      return "최대 가격"
            case .changeRateRange: return "최대 등락률"
            case .perRange:        return "최대 PER"
            case .pbrRange:        return "최대 PBR"
            case .marketCapRange:  return "최대 시가총액 (억)"
            default: return ""
            }
        }
    }
}
