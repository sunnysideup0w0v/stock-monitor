import Foundation
import AppKit

@MainActor
final class BackupManager {

    // MARK: - Backup Model

    struct Backup: Codable {
        var version: Int = 1
        var exportedAt: Date
        var watchlist: [WatchlistItem]
        var portfolio: [PortfolioItem]
        var alertConditions: [AlertCondition]
    }

    // MARK: - Export

    static func export() {
        let panel = NSSavePanel()
        panel.title = "설정 백업"
        panel.nameFieldStringValue = backupFileName()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let backup = try makeBackup()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backup)
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert(title: "백업 실패", message: error.localizedDescription)
        }
    }

    // MARK: - Import

    static func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "백업 파일 불러오기"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(Backup.self, from: data)
            try restore(from: backup)
        } catch {
            showAlert(title: "복원 실패", message: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func makeBackup() throws -> Backup {
        let watchlist = try DatabaseManager.shared.fetchWatchlist()
        let portfolio = try DatabaseManager.shared.fetchPortfolio()
        let conditions = try DatabaseManager.shared.fetchAlertConditions()
        return Backup(exportedAt: Date(), watchlist: watchlist, portfolio: portfolio, alertConditions: conditions)
    }

    static func restore(from backup: Backup) throws {
        let db = DatabaseManager.shared

        // watchlist — 기존 항목 유지, 심볼 중복 제외하고 추가
        let existingSymbols = Set((try? db.fetchWatchlist())?.map(\.symbol) ?? [])
        for item in backup.watchlist where !existingSymbols.contains(item.symbol) {
            var new = WatchlistItem(id: nil, symbol: item.symbol, name: item.name,
                                   alias: item.alias, group: item.group)
            try db.insert(&new)
        }

        // portfolio — 기존 항목 유지, 심볼 중복 제외하고 추가
        let existingPortfolioSymbols = Set((try? db.fetchPortfolio())?.map(\.symbol) ?? [])
        for item in backup.portfolio where !existingPortfolioSymbols.contains(item.symbol) {
            var new = PortfolioItem(id: nil, symbol: item.symbol, name: item.name,
                                   averagePrice: item.averagePrice, quantity: item.quantity)
            try db.insert(&new)
        }

        // alert_conditions — 전부 추가 (중복 허용, 동일 조건 복수 보유 가능)
        for condition in backup.alertConditions {
            var new = AlertCondition(id: nil, symbol: condition.symbol,
                                    triggerType: condition.triggerType,
                                    threshold: condition.threshold,
                                    isActive: condition.isActive,
                                    disableAfterTrigger: condition.disableAfterTrigger,
                                    cooldownMinutes: condition.cooldownMinutes,
                                    lastTriggeredAt: nil)
            try db.insert(&new)
        }

        showAlert(title: "복원 완료",
                  message: "관심종목 \(backup.watchlist.count)개, 포트폴리오 \(backup.portfolio.count)개, 알림 조건 \(backup.alertConditions.count)개를 가져왔습니다.")
    }

    private static func backupFileName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return "StockWatch-backup-\(fmt.string(from: Date())).json"
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
