import Foundation

final class MockBrokerAdapter: BrokerAdapter {
    let brokerName = "Mock"

    private let mockData: [String: (name: String, basePrice: Int)] = [
        "005930": ("삼성전자", 85_200),
        "000660": ("SK하이닉스", 165_500),
        "035420": ("NAVER", 180_000),
        "005380": ("현대차", 213_000),
        "051910": ("LG화학", 305_000),
        "035720": ("카카오", 42_500),
        "000270": ("기아", 89_700),
    ]

    func connect(credentials: BrokerCredentials) async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    func fetchQuote(symbol: String) async throws -> StockQuote {
        try await Task.sleep(for: .milliseconds(50))
        guard let data = mockData[symbol] else {
            throw BrokerError.symbolNotFound(symbol)
        }
        let fluctuation = Int.random(in: -500...500)
        let price = max(100, data.basePrice + fluctuation)
        let changeAmount = price - data.basePrice
        let changeRate = Double(changeAmount) / Double(data.basePrice) * 100
        return StockQuote(
            symbol: symbol,
            name: data.name,
            price: price,
            changeAmount: changeAmount,
            changeRate: changeRate,
            volume: Int.random(in: 100_000...10_000_000),
            timestamp: Date()
        )
    }

    func fetchPortfolio() async throws -> [PortfolioItem] {
        return []
    }

    func fetchNews(symbol: String) async throws -> [NewsItem] {
        return []
    }
}
