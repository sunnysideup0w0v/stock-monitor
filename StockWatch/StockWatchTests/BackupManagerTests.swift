import XCTest
@testable import StockWatch

final class BackupManagerTests: XCTestCase {

    private let testWatchSymbol = "TEST_BACKUP_W"
    private let testPortSymbol  = "TEST_BACKUP_P"

    override func setUp() async throws {
        try await super.setUp()
        AccountManager.testAccountId = "TEST-BACKUP-ACCOUNT"
    }

    override func tearDown() async throws {
        let watchSym = testWatchSymbol
        let portSym  = testPortSymbol
        await MainActor.run {
            let db = DatabaseManager.shared
            if let item = try? db.fetchWatchlist().first(where: { $0.symbol == watchSym }) {
                try? db.delete(item)
            }
            if let item = try? db.fetchPortfolio().first(where: { $0.symbol == portSym }) {
                try? db.delete(item)
            }
        }
        AccountManager.testAccountId = nil
        try await super.tearDown()
    }

    // MARK: - Backup Codable 라운드트립

    func test_backup_codableRoundtrip_preservesAllFields() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let watchItem = WatchlistItem(id: nil, symbol: "005930", name: "삼성전자", alias: "삼전", group: .longTerm)
        let portItem  = PortfolioItem(id: nil, symbol: "000660", name: "SK하이닉스", averagePrice: 130000, quantity: 10)
        let condition = AlertCondition(id: nil, symbol: "005930", triggerType: .targetPrice,
                                      threshold: 80000, isActive: true,
                                      disableAfterTrigger: false, cooldownMinutes: 60, lastTriggeredAt: nil)

        let original = BackupManager.Backup(
            version: 1, exportedAt: date,
            watchlist: [watchItem], portfolio: [portItem], alertConditions: [condition]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupManager.Backup.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.exportedAt.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decoded.watchlist.count, 1)
        XCTAssertEqual(decoded.watchlist[0].symbol, "005930")
        XCTAssertEqual(decoded.watchlist[0].alias, "삼전")
        XCTAssertEqual(decoded.watchlist[0].group, .longTerm)
        XCTAssertEqual(decoded.portfolio.count, 1)
        XCTAssertEqual(decoded.portfolio[0].averagePrice, 130000)
        XCTAssertEqual(decoded.portfolio[0].quantity, 10)
        XCTAssertEqual(decoded.alertConditions.count, 1)
        XCTAssertEqual(decoded.alertConditions[0].triggerType, .targetPrice)
        XCTAssertEqual(decoded.alertConditions[0].threshold, 80000)
    }

    func test_backup_defaultVersion_isOne() {
        let backup = BackupManager.Backup(exportedAt: Date(), watchlist: [], portfolio: [], alertConditions: [])
        XCTAssertEqual(backup.version, 1)
    }

    // MARK: - restore: 관심종목 삽입

    @MainActor func test_restore_insertsWatchlistItem() throws {
        let watchItem = WatchlistItem(id: nil, symbol: testWatchSymbol, name: "테스트종목", alias: nil, group: .watchlist)
        let backup = BackupManager.Backup(exportedAt: Date(), watchlist: [watchItem], portfolio: [], alertConditions: [])

        try BackupManager.restore(from: backup)

        let inserted = try DatabaseManager.shared.fetchWatchlist().first { $0.symbol == testWatchSymbol }
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.name, "테스트종목")
    }

    @MainActor func test_restore_skipsExistingWatchlistSymbol() throws {
        var existing = WatchlistItem(id: nil, symbol: testWatchSymbol, name: "원본이름", alias: nil, group: .watchlist)
        try DatabaseManager.shared.insert(&existing)

        let watchItem = WatchlistItem(id: nil, symbol: testWatchSymbol, name: "새이름", alias: nil, group: .watchlist)
        let backup = BackupManager.Backup(exportedAt: Date(), watchlist: [watchItem], portfolio: [], alertConditions: [])
        try BackupManager.restore(from: backup)

        let items = try DatabaseManager.shared.fetchWatchlist().filter { $0.symbol == testWatchSymbol }
        XCTAssertEqual(items.count, 1, "중복 심볼은 1개만 존재해야 함")
        XCTAssertEqual(items[0].name, "원본이름", "기존 항목이 덮어써지지 않아야 함")
    }

    // MARK: - restore: 포트폴리오 삽입

    @MainActor func test_restore_insertsPortfolioItem() throws {
        let portItem = PortfolioItem(id: nil, symbol: testPortSymbol, name: "테스트포트", averagePrice: 50000, quantity: 5)
        let backup = BackupManager.Backup(exportedAt: Date(), watchlist: [], portfolio: [portItem], alertConditions: [])

        try BackupManager.restore(from: backup)

        let inserted = try DatabaseManager.shared.fetchPortfolio().first { $0.symbol == testPortSymbol }
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.averagePrice, 50000)
        XCTAssertEqual(inserted?.quantity, 5)
    }
}
