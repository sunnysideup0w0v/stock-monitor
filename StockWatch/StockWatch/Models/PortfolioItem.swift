import Foundation
import GRDB

struct PortfolioItem: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var symbol: String
    var name: String
    var averagePrice: Int
    var quantity: Int
    var showInPopover: Bool = false
    var accountId: String = ""

    static let databaseTableName = "portfolio"

    init(id: Int64? = nil, symbol: String, name: String, averagePrice: Int, quantity: Int,
         showInPopover: Bool = false, accountId: String = "") {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.averagePrice = averagePrice
        self.quantity = quantity
        self.showInPopover = showInPopover
        self.accountId = accountId
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// accountId 접두사 기반 표시용 브로커 이름 ("KIS" / "키움" / …)
    var brokerName: String {
        if accountId.hasPrefix("KIS-") { return "KIS" }
        if accountId.hasPrefix("KIWOOM-") { return "키움" }
        return accountId
    }

    var totalCost: Int { averagePrice * quantity }

    func evaluatedGain(currentPrice: Int) -> Int {
        (currentPrice - averagePrice) * quantity
    }

    func gainRate(currentPrice: Int) -> Double {
        guard averagePrice > 0 else { return 0 }
        return Double(currentPrice - averagePrice) / Double(averagePrice) * 100
    }

    private enum CodingKeys: String, CodingKey {
        case id, symbol, name, averagePrice, quantity, showInPopover, accountId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        name = try c.decode(String.self, forKey: .name)
        averagePrice = try c.decode(Int.self, forKey: .averagePrice)
        quantity = try c.decode(Int.self, forKey: .quantity)
        showInPopover = (try c.decodeIfPresent(Bool.self, forKey: .showInPopover)) ?? false
        accountId = (try c.decodeIfPresent(String.self, forKey: .accountId)) ?? ""
    }
}
