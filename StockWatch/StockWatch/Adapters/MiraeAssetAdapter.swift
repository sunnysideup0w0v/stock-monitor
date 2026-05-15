import Foundation

/// 미래에셋증권 Open API 어댑터 (Stub — 추후 실 API 구현 예정)
///
/// 미래에셋증권 Open Trading Platform (https://openapi.miraeasset.com)
actor MiraeAssetAdapter: BrokerAdapter {
    nonisolated let brokerName = "미래에셋증권"

    private var credentials: BrokerCredentials?
    private var cachedToken: String?
    private var tokenExpiry: Date?

    private let baseURL = "https://openapi.miraeasset.com"

    // MARK: - BrokerAdapter

    func connect(credentials: BrokerCredentials) async throws {
        self.credentials = credentials
        // TODO: 미래에셋 OAuth 토큰 발급 구현
        throw BrokerError.apiError("미래에셋증권 어댑터는 아직 구현 중입니다.")
    }

    func disconnect() async {
        credentials = nil
        cachedToken = nil
        tokenExpiry = nil
    }

    func fetchQuote(symbol: String) async throws -> StockQuote {
        throw BrokerError.apiError("미래에셋증권 현재가 조회는 아직 구현 중입니다.")
    }

    func fetchPortfolio() async throws -> [PortfolioItem] {
        throw BrokerError.apiError("미래에셋증권 잔고조회는 아직 구현 중입니다.")
    }

    func fetchNews(symbol: String) async throws -> [NewsItem] {
        return []
    }

    func fetchDailyVolumes(symbol: String, days: Int) async throws -> [Int] {
        throw BrokerError.apiError("미래에셋증권 거래량 조회는 아직 구현 중입니다.")
    }
}
