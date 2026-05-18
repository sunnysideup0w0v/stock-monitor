import Foundation

@MainActor
final class SnapshotBackfillManager {
    static let shared = SnapshotBackfillManager()
    private init() {}

    private var isRunning = false

    private static var seoulCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }()

    // MARK: - Public

    func backfillIfNeeded() {
        guard !isRunning else { return }
        guard let appKey = KeychainHelper.load(account: KeychainKey.kisAppKey),
              let appSecret = KeychainHelper.load(account: KeychainKey.kisAppSecret),
              !appKey.isEmpty else { return }
        isRunning = true
        Task {
            await runBackfill(appKey: appKey, appSecret: appSecret)
            isRunning = false
        }
    }

    // MARK: - Backfill

    private func runBackfill(appKey: String, appSecret: String) async {
        guard let portfolio = try? DatabaseManager.shared.fetchPortfolio(),
              !portfolio.isEmpty else { return }

        let gapDays = findGapDays(lookbackDays: 32)
        guard !gapDays.isEmpty else { return }

        let isMock = UserDefaults.standard.bool(forKey: UserDefaultsKey.kisMock)
        let adapter = KISAdapter(isMock: isMock)
        let creds = BrokerCredentials(appKey: appKey, appSecret: appSecret, accountNumber: nil)
        do {
            try await adapter.connect(credentials: creds)
        } catch {
            AppLogger.log("Backfill: KIS 연결 실패 — \(error.localizedDescription)", level: .error, category: "App")
            return
        }

        // symbol -> (startOfDay -> closePrice)
        var closePriceMap: [String: [Date: Int]] = [:]
        for (index, item) in portfolio.enumerated() {
            if index > 0 { try? await Task.sleep(for: .milliseconds(200)) }
            do {
                let closes = try await adapter.fetchDailyCloses(symbol: item.symbol, days: 35)
                var map: [Date: Int] = [:]
                for c in closes {
                    map[Self.seoulCalendar.startOfDay(for: c.date)] = c.closePrice
                }
                closePriceMap[item.symbol] = map
            } catch {
                AppLogger.log("Backfill: \(item.symbol) 조회 실패 — \(error.localizedDescription)", level: .error, category: "App")
            }
        }

        var snapshots: [PortfolioSnapshot] = []
        let cal = Self.seoulCalendar

        for day in gapDays {
            var totalCost = 0
            var totalValue = 0
            var covered = 0

            for item in portfolio {
                guard let closePrice = closePriceMap[item.symbol]?[day] else { continue }
                totalCost  += item.averagePrice * item.quantity
                totalValue += closePrice * item.quantity
                covered    += 1
            }
            guard totalCost > 0, covered > 0 else { continue }

            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 15; comps.minute = 30; comps.second = 0
            comps.timeZone = TimeZone(identifier: "Asia/Seoul")
            guard let timestamp = cal.date(from: comps) else { continue }

            let gain = totalValue - totalCost
            let pct  = Double(gain) / Double(totalCost) * 100.0
            snapshots.append(PortfolioSnapshot(id: nil, timestamp: timestamp,
                                               totalValue: totalValue, totalGain: gain, gainPct: pct))
        }

        guard !snapshots.isEmpty else { return }
        try? DatabaseManager.shared.insertSnapshots(snapshots)
        AppLogger.log("Backfill: \(snapshots.count)일 소급 완료", level: .info, category: "App")
        NotificationCenter.default.post(name: .snapshotBackfillCompleted, object: nil)
    }

    // MARK: - Gap Detection

    func findGapDays(lookbackDays: Int) -> [Date] {
        let cal = Self.seoulCalendar
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -lookbackDays, to: today)!

        let existing = (try? DatabaseManager.shared.fetchSnapshots(from: start, to: today)) ?? []
        let daysWithData = Set(existing.map { cal.startOfDay(for: $0.timestamp) })

        var gaps: [Date] = []
        var cur = start
        while cur < today {
            let weekday = cal.component(.weekday, from: cur)
            if weekday != 1 && weekday != 7 && !daysWithData.contains(cur) {
                gaps.append(cur)
            }
            cur = cal.date(byAdding: .day, value: 1, to: cur)!
        }
        return gaps
    }
}
