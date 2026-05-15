import Foundation

/// 키움증권 REST API 어댑터 (Stub — Phase 4.4에서 실 API 구현 예정)
///
/// 키움 Open API+ (https://openapi.kiwoom.com) 는 macOS REST/WebSocket 방식을 지원한다.
/// 영웅문 COM API (Windows 전용)와는 별개의 경로.
actor KiwoomAdapter: BrokerAdapter {
    nonisolated let brokerName = "키움증권"

    private var credentials: BrokerCredentials?
    private var cachedToken: String?
    private var tokenExpiry: Date?

    private let baseURL = "https://openapi.kiwoom.com:10000"

    // MARK: - BrokerAdapter

    func connect(credentials: BrokerCredentials) async throws {
        self.credentials = credentials
        // TODO: POST /oauth2/token 으로 액세스 토큰 발급
        throw BrokerError.apiError("키움증권 어댑터는 아직 구현 중입니다.")
    }

    func disconnect() async {
        credentials = nil
        cachedToken = nil
        tokenExpiry = nil
    }

    func fetchQuote(symbol: String) async throws -> StockQuote {
        // TODO: GET /uapi/domestic-stock/v1/quotations/inquire-price (키움 엔드포인트 확인 필요)
        throw BrokerError.apiError("키움증권 현재가 조회는 아직 구현 중입니다.")
    }

    func fetchPortfolio() async throws -> [PortfolioItem] {
        // TODO: 잔고조회 API 연동
        throw BrokerError.apiError("키움증권 잔고조회는 아직 구현 중입니다.")
    }

    func fetchNews(symbol: String) async throws -> [NewsItem] {
        return []
    }

    func fetchDailyVolumes(symbol: String, days: Int) async throws -> [Int] {
        // TODO: 일별 거래량 API 연동
        throw BrokerError.apiError("키움증권 거래량 조회는 아직 구현 중입니다.")
    }
}
