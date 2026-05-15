import Foundation
import GRDB

struct WatchlistItem: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var symbol: String
    var name: String
    var alias: String?
    var group: WatchlistGroup
    var accountId: String = ""

    static let databaseTableName = "watchlist"

    init(id: Int64? = nil, symbol: String, name: String, alias: String? = nil,
         group: WatchlistGroup, accountId: String = "") {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.alias = alias
        self.group = group
        self.accountId = accountId
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    private enum CodingKeys: String, CodingKey {
        case id, symbol, name, alias, group, accountId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        name = try c.decode(String.self, forKey: .name)
        alias = try c.decodeIfPresent(String.self, forKey: .alias)
        group = try c.decode(WatchlistGroup.self, forKey: .group)
        accountId = (try c.decodeIfPresent(String.self, forKey: .accountId)) ?? ""
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
