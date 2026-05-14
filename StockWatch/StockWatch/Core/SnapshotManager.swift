import Foundation

@MainActor
final class SnapshotManager {
    static let shared = SnapshotManager()
    private init() {}

    private var task: Task<Void, Never>?

    var marketHoursOnly: Bool {
        get { UserDefaults.standard.object(forKey: "Snapshot.marketHoursOnly") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "Snapshot.marketHoursOnly") }
    }

    func start() {
        stop()
        task = Task {
            while !Task.isCancelled {
                takeSnapshot()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func takeSnapshot() {
        if marketHoursOnly && !isMarketHours() { return }

        guard let portfolio = try? DatabaseManager.shared.fetchPortfolio(),
              !portfolio.isEmpty else { return }

        let quotes = QuoteManager.shared.quotes
        var totalCost  = 0
        var totalValue = 0

        for item in portfolio {
            guard let quote = quotes[item.symbol] else { continue }
            totalCost  += item.averagePrice * item.quantity
            totalValue += quote.price * item.quantity
        }
        guard totalCost > 0 else { return }

        let gain = totalValue - totalCost
        let pct  = Double(gain) / Double(totalCost) * 100.0

        var snapshot = PortfolioSnapshot(
            id: nil,
            timestamp: Date(),
            totalValue: totalValue,
            totalGain: gain,
            gainPct: pct
        )
        try? DatabaseManager.shared.insert(&snapshot)
        try? DatabaseManager.shared.cleanupSnapshots()
    }

    // 평일 09:00~15:30 (한국 장 시간)
    private func isMarketHours() -> Bool {
        let cal     = Calendar.current
        let now     = Date()
        let weekday = cal.component(.weekday, from: now) // 1=일, 7=토
        guard weekday != 1 && weekday != 7 else { return false }

        let hour    = cal.component(.hour,   from: now)
        let minute  = cal.component(.minute, from: now)
        let minutes = hour * 60 + minute
        return minutes >= 9 * 60 && minutes <= 15 * 60 + 30
    }
}
