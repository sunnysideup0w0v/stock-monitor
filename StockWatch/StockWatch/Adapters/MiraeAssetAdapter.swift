import Foundation

#warning("미래에셋 어댑터 미구현 — 구현 계획 확정 전까지 stub 유지")
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

    func fetchDailyVolumes(symbol: String, days: Int) async throws -> [Int] {
        throw BrokerError.apiError("미래에셋증권 거래량 조회는 아직 구현 중입니다.")
    }
}
