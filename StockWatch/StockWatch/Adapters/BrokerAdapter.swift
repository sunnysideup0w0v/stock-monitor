import Foundation

struct BrokerCredentials: Sendable {
    let appKey: String
    let appSecret: String
    let accountNumber: String?
}

enum BrokerError: Error, Sendable {
    case notConnected
    case symbolNotFound(String)
    case apiError(String)
    case tokenExpired
}

extension BrokerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "브로커에 연결되어 있지 않습니다."
        case .symbolNotFound(let symbol):
            return "종목 현재가를 받아오지 못했습니다 (\(symbol)) — 장 마감 시간이거나 종목코드를 확인해주세요."
        case .apiError(let message):
            return "API 오류: \(message)"
        case .tokenExpired:
            return "액세스 토큰이 만료되었습니다."
        }
    }
}

protocol BrokerAdapter: Sendable {
    var brokerName: String { get }
    func connect(credentials: BrokerCredentials) async throws
    func disconnect() async
    func fetchQuote(symbol: String) async throws -> StockQuote
    func fetchPortfolio() async throws -> [PortfolioItem]
    /// 최근 N 영업일의 일별 거래량을 최신순으로 반환
    func fetchDailyVolumes(symbol: String, days: Int) async throws -> [Int]
}
