import Foundation

actor KISAdapter: BrokerAdapter {
    nonisolated let brokerName = "한국투자증권"

    private let isMock: Bool
    private var credentials: BrokerCredentials?
    private var cachedToken: String?
    private var tokenExpiry: Date?

    private var baseURL: String {
        isMock
            ? "https://openapivts.koreainvestment.com:29443"
            : "https://openapi.koreainvestment.com:9443"
    }

    private var quoteTrID: String {
        isMock ? "VHKST01010100" : "FHKST01010100"
    }

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    // MARK: - BrokerAdapter

    func connect(credentials: BrokerCredentials) async throws {
        self.credentials = credentials
        try await issueToken()
    }

    func fetchQuote(symbol: String) async throws -> StockQuote {
        let token = try await validToken()
        guard let creds = credentials else { throw BrokerError.notConnected }

        var components = URLComponents(
            string: "\(baseURL)/uapi/domestic-stock/v1/quotations/inquire-price"
        )!
        components.queryItems = [
            URLQueryItem(name: "FID_COND_MRKT_DIV_CODE", value: "J"),
            URLQueryItem(name: "FID_INPUT_ISCD", value: symbol)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(creds.appKey, forHTTPHeaderField: "appkey")
        request.setValue(creds.appSecret, forHTTPHeaderField: "appsecret")
        request.setValue(quoteTrID, forHTTPHeaderField: "tr_id")
        request.setValue("P", forHTTPHeaderField: "custtype")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw BrokerError.apiError("응답 오류")
        }

        // 토큰 만료 시 재발급 후 1회 재시도
        if http.statusCode == 401 {
            cachedToken = nil
            tokenExpiry = nil
            try await issueToken()
            return try await fetchQuote(symbol: symbol)
        }

        guard http.statusCode == 200 else {
            throw BrokerError.apiError("HTTP \(http.statusCode)")
        }

        // 디버그: 원시 응답 출력
        if let rawString = String(data: data, encoding: .utf8) {
            print("[KISAdapter] fetchQuote response: \(rawString.prefix(500))")
        }

        let decoded = try JSONDecoder().decode(KISQuoteResponse.self, from: data)

        guard decoded.rtCd == "0", let output = decoded.output else {
            let msg = decoded.msg1 ?? "알 수 없는 오류"
            print("[KISAdapter] rt_cd=\(decoded.rtCd), msg=\(msg)")
            throw BrokerError.apiError(msg)
        }

        let priceStr = output.stckPrpr ?? "0"
        print("[KISAdapter] stck_prpr=\(priceStr), name=\(output.htsKorIsnm ?? "(nil)")")
        let price = Int(priceStr) ?? 0
        guard price > 0 else { throw BrokerError.symbolNotFound(symbol) }

        // prdy_vrss_sign: 1=상한 2=상승 3=보합 4=하락 5=하한
        let absChange = Int(output.prdyVrss ?? "0") ?? 0
        let sign = output.prdyVrssSign ?? "3"
        let isNegative = sign == "4" || sign == "5"
        let changeAmount = isNegative ? -absChange : absChange
        let changeRate = Double(output.prdyCtrt ?? "0") ?? 0

        return StockQuote(
            symbol: symbol,
            name: output.htsKorIsnm ?? symbol,
            price: price,
            changeAmount: changeAmount,
            changeRate: changeRate,
            volume: Int(output.acmlVol ?? "0") ?? 0,
            timestamp: Date()
        )
    }

    func fetchPortfolio() async throws -> [PortfolioItem] {
        // Phase 4에서 KIS 잔고조회 API 연동 예정
        return []
    }

    func fetchNews(symbol: String) async throws -> [NewsItem] {
        return []
    }

    func fetchDailyVolumes(symbol: String, days: Int) async throws -> [Int] {
        let token = try await validToken()
        guard let creds = credentials else { throw BrokerError.notConnected }

        let trID = isMock ? "VHKST01010400" : "FHKST01010400"

        var components = URLComponents(
            string: "\(baseURL)/uapi/domestic-stock/v1/quotations/inquire-daily-price"
        )!
        components.queryItems = [
            URLQueryItem(name: "FID_COND_MRKT_DIV_CODE", value: "J"),
            URLQueryItem(name: "FID_INPUT_ISCD", value: symbol),
            URLQueryItem(name: "FID_PERIOD_DIV_CODE", value: "D"),
            URLQueryItem(name: "FID_ORG_ADJ_PRC", value: "0")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(creds.appKey, forHTTPHeaderField: "appkey")
        request.setValue(creds.appSecret, forHTTPHeaderField: "appsecret")
        request.setValue(trID, forHTTPHeaderField: "tr_id")
        request.setValue("P", forHTTPHeaderField: "custtype")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BrokerError.apiError("일별 시세 조회 실패")
        }

        let decoded = try JSONDecoder().decode(KISDailyPriceResponse.self, from: data)
        guard decoded.rtCd == "0" else {
            throw BrokerError.apiError(decoded.msg1 ?? "일별 시세 오류")
        }

        return (decoded.output2 ?? [])
            .prefix(days)
            .compactMap { Int($0.acmlVol ?? "0") }
    }

    // MARK: - Token Management

    private func validToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }
        try await issueToken()
        guard let token = cachedToken else { throw BrokerError.tokenExpired }
        return token
    }

    private func issueToken() async throws {
        guard let creds = credentials else { throw BrokerError.notConnected }

        let url = URL(string: "\(baseURL)/oauth2/tokenP")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "client_credentials",
            "appkey": creds.appKey,
            "appsecret": creds.appSecret
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        let tokenStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
        if let raw = String(data: data, encoding: .utf8) {
            print("[KISAdapter] token response (\(tokenStatus)): \(raw.prefix(300))")
        }

        guard tokenStatus == 200 else {
            throw BrokerError.apiError("토큰 발급 실패 (HTTP \(tokenStatus)) — API 키를 확인해주세요")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }

        let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = tr.access_token
        // 만료 5분 전에 갱신되도록 여유를 둠
        tokenExpiry = Date().addingTimeInterval(Double(tr.expires_in) - 300)
    }
}

// MARK: - Response Models

private struct KISDailyPriceResponse: Decodable {
    let rtCd: String
    let msg1: String?
    let output2: [KISDailyOutput]?

    enum CodingKeys: String, CodingKey {
        case rtCd = "rt_cd"
        case msg1
        case output2
    }
}

private struct KISDailyOutput: Decodable {
    let acmlVol: String?

    enum CodingKeys: String, CodingKey {
        case acmlVol = "acml_vol"
    }
}

private struct KISQuoteResponse: Decodable {
    let rtCd: String
    let msg1: String?
    let output: KISQuoteOutput?

    enum CodingKeys: String, CodingKey {
        case rtCd = "rt_cd"
        case msg1
        case output
    }
}

private struct KISQuoteOutput: Decodable {
    let htsKorIsnm: String?
    let stckPrpr: String?
    let prdyVrss: String?
    let prdyVrssSign: String?
    let prdyCtrt: String?
    let acmlVol: String?

    enum CodingKeys: String, CodingKey {
        case htsKorIsnm   = "hts_kor_isnm"
        case stckPrpr     = "stck_prpr"
        case prdyVrss     = "prdy_vrss"
        case prdyVrssSign = "prdy_vrss_sign"
        case prdyCtrt     = "prdy_ctrt"
        case acmlVol      = "acml_vol"
    }
}
