import Foundation
import GRDB

struct WatchlistItem: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var symbol: String
    var name: String
    var alias: String?
    var group: WatchlistGroup

    static let databaseTableName = "watchlist"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

enum WatchlistGroup: String, Codable {
    case longTerm = "long_term"
    case shortTerm = "short_term"
    case watchlist = "watchlist"

    var displayName: String {
        switch self {
        case .longTerm: return "장기보유"
        case .shortTerm: return "단기매매"
        case .watchlist: return "관심"
        }
    }
}
