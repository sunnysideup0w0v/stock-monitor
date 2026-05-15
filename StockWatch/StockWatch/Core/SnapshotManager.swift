import Foundation

// 커스텀 수집 시간대 (UserDefaults JSON 직렬화)
struct SnapshotTimeRange: Codable, Identifiable {
    var id: UUID
    var startMinute: Int  // 자정 기준 분, 예) 07:00 = 420
    var endMinute: Int    // 예) 09:00 = 540

    init(startMinute: Int, endMinute: Int) {
        self.id = UUID()
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    var displayString: String {
        String(format: "%02d:%02d ~ %02d:%02d",
               startMinute / 60, startMinute % 60,
               endMinute   / 60, endMinute   % 60)
    }
}

@MainActor
final class SnapshotManager {
    static let shared = SnapshotManager()
    private init() {}

    private var task: Task<Void, Never>?

    // MARK: - Settings (UserDefaults)

    var marketHoursOnly: Bool {
        get { UserDefaults.standard.object(forKey: "Snapshot.marketHoursOnly") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "Snapshot.marketHoursOnly") }
    }

    var customRanges: [SnapshotTimeRange] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "Snapshot.customRanges"),
                  let ranges = try? JSONDecoder().decode([SnapshotTimeRange].self, from: data)
            else { return [] }
            return ranges
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: "Snapshot.customRanges")
        }
    }

    // -1 = 무제한, 0 = 미설정(기본값 365일 적용), 양수 = 보존 일수
    var keepDays: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "Snapshot.keepDays")
            return v == 0 ? 365 : v  // 미설정(0) → 기본 365일
        }
        set { UserDefaults.standard.set(newValue, forKey: "Snapshot.keepDays") }
    }

    // MARK: - Lifecycle

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

    // MARK: - Snapshot

    private func takeSnapshot() {
        guard isActiveTime() else { return }

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

        let kd = keepDays
        if kd > 0 {  // -1(무제한) 또는 0(미설정) 시 정리 안 함
            try? DatabaseManager.shared.cleanupSnapshots(keepDays: kd)
        }
    }

    // MARK: - Time Check

    private func isActiveTime() -> Bool {
        let cal     = Calendar.current
        let now     = Date()
        let weekday = cal.component(.weekday, from: now) // 1=일, 7=토
        let hour    = cal.component(.hour,   from: now)
        let minute  = cal.component(.minute, from: now)
        let current = hour * 60 + minute

        // 장 시간 체크 (평일 09:00~15:30)
        if marketHoursOnly && weekday != 1 && weekday != 7 {
            if current >= 9 * 60 && current <= 15 * 60 + 30 { return true }
        }

        // 커스텀 시간대 체크 (요일 무관)
        return customRanges.contains { current >= $0.startMinute && current <= $0.endMinute }
    }
}
