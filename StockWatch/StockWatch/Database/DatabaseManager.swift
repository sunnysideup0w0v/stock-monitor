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

        try migrator.migrate(dbQueue)
    }

    // MARK: - Watchlist

    func fetchWatchlist() throws -> [WatchlistItem] {
        try dbQueue.read { db in try WatchlistItem.fetchAll(db) }
    }

    func insert(_ item: inout WatchlistItem) throws {
        try dbQueue.write { db in try item.insert(db) }
    }

    func update(_ item: WatchlistItem) throws {
        try dbQueue.write { db in try item.update(db) }
    }

    func delete(_ item: WatchlistItem) throws {
        try dbQueue.write { db in _ = try item.delete(db) }
    }

    // MARK: - Portfolio

    func fetchPortfolio() throws -> [PortfolioItem] {
        try dbQueue.read { db in try PortfolioItem.fetchAll(db) }
    }

    func insert(_ item: inout PortfolioItem) throws {
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
}
