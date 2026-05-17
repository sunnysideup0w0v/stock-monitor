import Foundation
import GRDB

final class ScreenerEngine: @unchecked Sendable {
    static let shared = ScreenerEngine()
    private init() {}

    func run(conditions: [ScreenerCondition], limit: Int = 300) throws -> [StockUniverseItem] {
        var request = StockUniverseItem.all()

        for cond in conditions where cond.isEnabled {
            request = apply(cond, to: request)
        }

        request = request.order(Column("marketCap").desc).limit(limit)
        return try DatabaseManager.shared.fetchStockUniverse(matching: request)
    }

    func availableSectors() throws -> [String] {
        try DatabaseManager.shared.fetchDistinctValues(column: "sector", table: "stock_universe")
    }

    func availableMarkets() throws -> [String] {
        try DatabaseManager.shared.fetchDistinctValues(column: "market", table: "stock_universe")
    }

    private func multiValues(_ cond: ScreenerCondition) -> [String] {
        (cond.stringValue ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private func apply(
        _ cond: ScreenerCondition,
        to req: QueryInterfaceRequest<StockUniverseItem>
    ) -> QueryInterfaceRequest<StockUniverseItem> {
        var r = req
        switch cond.type {
        case .priceRange:
            if let min = cond.minValue { r = r.filter(Column("close") >= Int(min)) }
            if let max = cond.maxValue { r = r.filter(Column("close") <= Int(max)) }

        case .volumeMin:
            if let min = cond.minValue { r = r.filter(Column("volume") >= Int(min)) }

        case .changeRateRange:
            // (종가 - 시가) / 시가 × 100 — 당일 시가 대비 변화율 근사
            let expr = "CAST(close - open AS REAL) * 100.0 / NULLIF(open, 0)"
            if let min = cond.minValue {
                r = r.filter(sql: "(\(expr)) >= ?", arguments: [min])
            }
            if let max = cond.maxValue {
                r = r.filter(sql: "(\(expr)) <= ?", arguments: [max])
            }

        case .perRange:
            r = r.filter(Column("per") != nil)
            if let min = cond.minValue { r = r.filter(Column("per") >= min) }
            if let max = cond.maxValue { r = r.filter(Column("per") <= max) }

        case .pbrRange:
            r = r.filter(Column("pbr") != nil)
            if let min = cond.minValue { r = r.filter(Column("pbr") >= min) }
            if let max = cond.maxValue { r = r.filter(Column("pbr") <= max) }

        case .marketCapRange:
            // UI 입력: 억원 / DB 저장: 백만원 (1억 = 100 백만)
            if let min = cond.minValue { r = r.filter(Column("marketCap") >= Int(min * 100)) }
            if let max = cond.maxValue { r = r.filter(Column("marketCap") <= Int(max * 100)) }

        case .sectorFilter:
            let sectors = multiValues(cond)
            if !sectors.isEmpty { r = r.filter(sectors.contains(Column("sector"))) }

        case .marketFilter:
            let markets = multiValues(cond)
            if !markets.isEmpty { r = r.filter(markets.contains(Column("market"))) }

        case .instrumentType:
            let values = multiValues(cond)
            if values.count == 1 {
                r = r.filter(Column("isEtf") == (values[0] == "ETF"))
            }
            // 둘 다 or 없음 → 필터 없음
        }
        return r
    }
}
