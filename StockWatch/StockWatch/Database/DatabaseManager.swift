import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue!

    private init() {
        do {
            try setup()
        } catch {
            fatalError("DatabaseManager 초기화 실패: \(error)")
        }
    }

    private func setup() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("StockWatch")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("stockwatch.db").path
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_watchlist") { db in
            try db.create(table: "watchlist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("symbol", .text).notNull()
                t.column("name", .text).notNull()
                t.column("alias", .text)
                t.column("group", .text).notNull().defaults(to: "watchlist")
            }
        }

        migrator.registerMigration("v2_portfolio") { db in
            try db.create(table: "portfolio") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("symbol", .text).notNull()
                t.column("name", .text).notNull()
                t.column("averagePrice", .integer).notNull()
                t.column("quantity", .integer).notNull()
            }
        }

        migrator.registerMigration("v3_alert_conditions") { db in
            try db.create(table: "alert_conditions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("symbol", .text).notNull()
                t.column("triggerType", .text).notNull()
                t.column("threshold", .double).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("disableAfterTrigger", .boolean).notNull().defaults(to: false)
                t.column("cooldownMinutes", .integer).notNull().defaults(to: 60)
                t.column("lastTriggeredAt", .datetime)
            }
        }

        migrator.registerMigration("v4_alert_history") { db in
            try db.create(table: "alert_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("symbol", .text).notNull()
                t.column("triggerType", .text).notNull()
                t.column("message", .text).notNull()
                t.column("triggeredAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v5_alert_history_metadata") { db in
            try db.alter(table: "alert_history") { t in
                t.add(column: "metadata", .text)
            }
        }

        migrator.registerMigration("v6_portfolio_snapshots") { db in
            try db.create(table: "portfolio_snapshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp",  .datetime).notNull()
                t.column("totalValue", .integer).notNull()
                t.column("totalGain",  .integer).notNull()
                t.column("gainPct",    .double).notNull()
            }
        }

        migrator.registerMigration("v7_portfolio_show_in_popover") { db in
            try db.alter(table: "portfolio") { t in
                t.add(column: "showInPopover", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v8_account_id") { db in
            try db.alter(table: "watchlist") { t in
                t.add(column: "accountId", .text).notNull().defaults(to: "")
            }
            try db.alter(table: "portfolio") { t in
                t.add(column: "accountId", .text).notNull().defaults(to: "")
            }
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Account Migration

    /// 기존 accountId == "" 행을 현재 계정으로 일회성 마이그레이션.
    /// UserDefaults "DB.v8AccountIdMigrated" 플래그로 중복 실행 방지.
    func assignAccountIdToOrphanedItems(accountId: String) throws {
        guard !accountId.isEmpty,
              !UserDefaults.standard.bool(forKey: "DB.v8AccountIdMigrated") else { return }
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE watchlist SET accountId = ? WHERE accountId = ''",
                           arguments: [accountId])
            try db.execute(sql: "UPDATE portfolio SET accountId = ? WHERE accountId = ''",
                           arguments: [accountId])
        }
        UserDefaults.standard.set(true, forKey: "DB.v8AccountIdMigrated")
    }

    // MARK: - Watchlist

    func fetchWatchlist() throws -> [WatchlistItem] {
        // 관심종목은 브로커 무관 — 어느 계좌든 연결 시 전체 표시, 로그아웃 시만 빈 배열
        guard AccountManager.isAnyConnected else { return [] }
        return try dbQueue.read { db in
            try WatchlistItem.filter(Column("accountId") != "").fetchAll(db)
        }
    }

    func insert(_ item: inout WatchlistItem) throws {
        item.accountId = AccountManager.currentAccountId
        try dbQueue.write { db in try item.insert(db) }
    }

    func update(_ item: WatchlistItem) throws {
        try dbQueue.write { db in try item.update(db) }
    }

    func delete(_ item: WatchlistItem) throws {
        try dbQueue.write { db in _ = try item.delete(db) }
    }

    // MARK: - Portfolio

    /// 현재 연결된 모든 브로커의 포트폴리오 항목 반환.
    func fetchPortfolio() throws -> [PortfolioItem] {
        let ids = AccountManager.connectedAccountIds
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in
            try PortfolioItem.filter(ids.contains(Column("accountId"))).fetchAll(db)
        }
    }

    /// 특정 브로커의 포트폴리오 항목만 반환 (포트폴리오 탭 브로커 필터용).
    func fetchPortfolio(for accountId: String) throws -> [PortfolioItem] {
        return try dbQueue.read { db in
            try PortfolioItem.filter(Column("accountId") == accountId).fetchAll(db)
        }
    }

    func insert(_ item: inout PortfolioItem) throws {
        item.accountId = AccountManager.currentAccountId
        try dbQueue.write { db in try item.insert(db) }
    }

    func update(_ item: PortfolioItem) throws {
        try dbQueue.write { db in try item.update(db) }
    }

    func delete(_ item: PortfolioItem) throws {
        try dbQueue.write { db in _ = try item.delete(db) }
    }

    // MARK: - AlertConditions

    func fetchAlertConditions() throws -> [AlertCondition] {
        try dbQueue.read { db in try AlertCondition.fetchAll(db) }
    }

    func insert(_ condition: inout AlertCondition) throws {
        try dbQueue.write { db in try condition.insert(db) }
    }

    func update(_ condition: AlertCondition) throws {
        try dbQueue.write { db in try condition.update(db) }
    }

    func delete(_ condition: AlertCondition) throws {
        try dbQueue.write { db in _ = try condition.delete(db) }
    }

    // MARK: - AlertHistory

    func fetchAlertHistory(limit: Int = 100) throws -> [AlertHistory] {
        try dbQueue.read { db in
            try AlertHistory.order(Column("triggeredAt").desc).limit(limit).fetchAll(db)
        }
    }

    func insert(_ history: inout AlertHistory) throws {
        try dbQueue.write { db in try history.insert(db) }
    }

    /// 알림 이력 저장 + 쿨다운 업데이트를 단일 트랜잭션으로 처리
    /// 둘 중 하나라도 실패하면 모두 롤백되어 중복 알림을 방지한다
    func recordAlertFired(history: inout AlertHistory, condition: AlertCondition) throws {
        try dbQueue.write { db in
            try history.insert(db)
            try condition.update(db)
        }
    }

    // MARK: - Portfolio Snapshots

    func insert(_ snapshot: inout PortfolioSnapshot) throws {
        try dbQueue.write { db in try snapshot.insert(db) }
    }

    func insertSnapshots(_ snapshots: [PortfolioSnapshot]) throws {
        try dbQueue.write { db in
            for var s in snapshots { try s.insert(db) }
        }
    }

    func fetchSnapshots(from start: Date, to end: Date) throws -> [PortfolioSnapshot] {
        try dbQueue.read { db in
            try PortfolioSnapshot
                .filter(Column("timestamp") >= start && Column("timestamp") <= end)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }

    func cleanupSnapshots(keepDays: Int = 365) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()
        try dbQueue.write { db in
            try PortfolioSnapshot.filter(Column("timestamp") < cutoff).deleteAll(db)
        }
    }

    func snapshotStats() throws -> (count: Int, oldest: Date?, newest: Date?) {
        try dbQueue.read { db in
            let count  = try PortfolioSnapshot.fetchCount(db)
            let oldest = try PortfolioSnapshot.order(Column("timestamp").asc).fetchOne(db)?.timestamp
            let newest = try PortfolioSnapshot.order(Column("timestamp").desc).fetchOne(db)?.timestamp
            return (count, oldest, newest)
        }
    }

    func deleteAllSnapshots() throws {
        try dbQueue.write { db in try PortfolioSnapshot.deleteAll(db) }
    }
}
