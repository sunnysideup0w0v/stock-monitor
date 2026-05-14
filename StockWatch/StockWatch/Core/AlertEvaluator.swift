import Foundation

@MainActor
final class AlertEvaluator {
    static let shared = AlertEvaluator()
    private init() {}

    func evaluate(quotes: [String: StockQuote]) {
        guard let conditions = try? DatabaseManager.shared.fetchAlertConditions() else { return }
        let now = Date()

        for (_, quote) in quotes {
            let symbolConditions = conditions.filter {
                $0.symbol == quote.symbol && $0.isActive && !$0.triggerType.isPortfolioLevel
            }
            for condition in symbolConditions {
                guard canFire(condition: condition, now: now) else { continue }
                guard isTriggered(quote: quote, condition: condition) else { continue }
                fire(quote: quote, condition: condition, now: now)
            }
        }

        evaluatePortfolio(conditions: conditions, quotes: quotes, now: now)
    }

    private func canFire(condition: AlertCondition, now: Date) -> Bool {
        guard let last = condition.lastTriggeredAt else { return true }
        return now.timeIntervalSince(last) >= Double(condition.cooldownMinutes * 60)
    }

    private func isTriggered(quote: StockQuote, condition: AlertCondition) -> Bool {
        switch condition.triggerType {
        case .targetPrice: return Double(quote.price) >= condition.threshold
        case .stopLoss:    return Double(quote.price) <= condition.threshold
        case .rateUp:      return quote.changeRate >= condition.threshold
        case .rateDown:    return quote.changeRate <= -condition.threshold
        case .volumeSpike:
            let avgVol = QuoteManager.shared.avgVolumes[condition.symbol] ?? 0
            guard avgVol > 0 else { return false }
            return quote.volume >= Int(Double(avgVol) * condition.threshold)
        case .portfolioGain, .portfolioLoss, .portfolioGainRate, .portfolioLossRate:
            return false // evaluatePortfolio()에서 별도 처리
        case .dartDisclosure:
            return false // DARTManager에서 별도 처리
        }
    }

    private func evaluatePortfolio(conditions: [AlertCondition], quotes: [String: StockQuote], now: Date) {
        let portfolioConditions = conditions.filter { $0.isActive && $0.triggerType.isPortfolioLevel }
        guard !portfolioConditions.isEmpty else { return }
        guard let portfolio = try? DatabaseManager.shared.fetchPortfolio(), !portfolio.isEmpty else { return }

        var totalCost = 0
        var totalValue = 0
        for item in portfolio {
            guard let quote = quotes[item.symbol] else { continue }
            totalCost += item.averagePrice * item.quantity
            totalValue += quote.price * item.quantity
        }
        guard totalCost > 0 else { return }

        let totalGain = totalValue - totalCost
        let gainRate = Double(totalGain) / Double(totalCost) * 100.0

        for condition in portfolioConditions {
            guard canFire(condition: condition, now: now) else { continue }
            let triggered: Bool
            switch condition.triggerType {
            case .portfolioGain:     triggered = Double(totalGain) >= condition.threshold
            case .portfolioLoss:     triggered = Double(totalGain) <= -condition.threshold
            case .portfolioGainRate: triggered = gainRate >= condition.threshold
            case .portfolioLossRate: triggered = gainRate <= -condition.threshold
            default:                 triggered = false
            }
            guard triggered else { continue }

            let message = makePortfolioMessage(totalGain: totalGain, gainRate: gainRate, condition: condition)
            NotificationManager.shared.send(title: "포트폴리오 알림", body: message, symbol: "PORTFOLIO")

            var updated = condition
            updated.lastTriggeredAt = now
            if condition.disableAfterTrigger { updated.isActive = false }
            var history = AlertHistory(id: nil, symbol: "PORTFOLIO", triggerType: condition.triggerType,
                                       message: message, triggeredAt: now)
            try? DatabaseManager.shared.recordAlertFired(history: &history, condition: updated)
        }
    }

    private func makePortfolioMessage(totalGain: Int, gainRate: Double, condition: AlertCondition) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        func fmtAmt(_ v: Int) -> String { fmt.string(from: NSNumber(value: abs(v))) ?? "\(abs(v))" }

        switch condition.triggerType {
        case .portfolioGain:
            return String(format: "목표 손익 +%@원 달성 (현재: %@%@원, %+.2f%%)",
                          fmtAmt(Int(condition.threshold)),
                          totalGain >= 0 ? "+" : "-", fmtAmt(totalGain), gainRate)
        case .portfolioLoss:
            return String(format: "손절 기준 -%@원 도달 (현재: -%@원, %+.2f%%)",
                          fmtAmt(Int(condition.threshold)), fmtAmt(totalGain), gainRate)
        case .portfolioGainRate:
            return String(format: "목표 수익률 +%.1f%% 달성 (현재: %@%@원, %+.2f%%)",
                          condition.threshold,
                          totalGain >= 0 ? "+" : "-", fmtAmt(totalGain), gainRate)
        case .portfolioLossRate:
            return String(format: "손절 수익률 -%.1f%% 도달 (현재: -%@원, %+.2f%%)",
                          condition.threshold, fmtAmt(totalGain), gainRate)
        default:
            return "포트폴리오 알림"
        }
    }

    private func fire(quote: StockQuote, condition: AlertCondition, now: Date) {
        let message = makeMessage(quote: quote, condition: condition)
        NotificationManager.shared.send(title: "[\(quote.name)] 알림", body: message, symbol: quote.symbol)

        var updated = condition
        updated.lastTriggeredAt = now
        if condition.disableAfterTrigger { updated.isActive = false }

        // 이력 저장 + 쿨다운 업데이트를 단일 트랜잭션으로 — 쿨다운 미적용으로 인한 중복 알림 방지
        var history = AlertHistory(id: nil, symbol: quote.symbol, triggerType: condition.triggerType, message: message, triggeredAt: now)
        try? DatabaseManager.shared.recordAlertFired(history: &history, condition: updated)
    }

    private func makeMessage(quote: StockQuote, condition: AlertCondition) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal

        func fmtPrice(_ v: Int) -> String { fmt.string(from: NSNumber(value: v)) ?? "\(v)" }

        switch condition.triggerType {
        case .targetPrice:
            return "목표가 \(fmtPrice(Int(condition.threshold)))원 도달 (현재가: \(fmtPrice(quote.price))원)"
        case .stopLoss:
            return "손절가 \(fmtPrice(Int(condition.threshold)))원 도달 (현재가: \(fmtPrice(quote.price))원)"
        case .rateUp:
            return String(format: "등락률 +%.1f%% 도달 (현재: %+.2f%%)", condition.threshold, quote.changeRate)
        case .rateDown:
            return String(format: "등락률 -%.1f%% 도달 (현재: %+.2f%%)", condition.threshold, quote.changeRate)
        case .volumeSpike:
            let avgVol = QuoteManager.shared.avgVolumes[quote.symbol] ?? 0
            let multiple = avgVol > 0 ? Double(quote.volume) / Double(avgVol) : 0
            return String(format: "거래량 급증 %.1f배 (현재: %@, 5일평균: %@)",
                          multiple,
                          fmt.string(from: NSNumber(value: quote.volume)) ?? "",
                          fmt.string(from: NSNumber(value: avgVol)) ?? "")
        case .portfolioGain, .portfolioLoss, .portfolioGainRate, .portfolioLossRate:
            return "포트폴리오 알림" // makePortfolioMessage에서 별도 생성
        case .dartDisclosure:
            return "DART 공시"
        }
    }
}
