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

    func disconnect() async {
        credentials = nil
        cachedToken = nil
        tokenExpiry = nil
    }

    func fetchQuote(symbol: String) async throws -> StockQuote {
        try await fetchQuote(symbol: symbol, retryOnUnauthorized: true, retryCount: 1)
    }

    private func fetchQuote(symbol: String, retryOnUnauthorized: Bool, retryCount: Int) async throws -> StockQuote {
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

        // 토큰 만료 시 재발급 후 1회만 재시도 — retryOnUnauthorized=false면 바로 에러
        if http.statusCode == 401 {
            guard retryOnUnauthorized else { throw BrokerError.tokenExpired }
            cachedToken = nil
            tokenExpiry = nil
            try await issueToken()
            return try await fetchQuote(symbol: symbol, retryOnUnauthorized: false, retryCount: retryCount)
        }

        // 403/503: 일시적 서버 오류 — retryCount 남아 있으면 1초 후 재시도
        if http.statusCode == 403 || http.statusCode == 503 {
            guard retryCount > 0 else { throw BrokerError.apiError("HTTP \(http.statusCode)") }
            try? await Task.sleep(for: .seconds(1))
            return try await fetchQuote(symbol: symbol, retryOnUnauthorized: retryOnUnauthorized, retryCount: retryCount - 1)
        }

        guard http.statusCode == 200 else {
            throw BrokerError.apiError("HTTP \(http.statusCode)")
        }

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
        let token = try await validToken()
        guard let creds = credentials else { throw BrokerError.notConnected }
        guard let acctNo = creds.accountNumber, !acctNo.isEmpty else {
            throw BrokerError.apiError("계좌번호를 설정해 주세요")
        }

        // "50123456-01" → CANO="50123456", ACNT_PRDT_CD="01"
        let cleaned = acctNo.replacingOccurrences(of: "-", with: "")
        let cano: String
        let acntPrdtCd: String
        if cleaned.count >= 10 {
            cano = String(cleaned.prefix(8))
            acntPrdtCd = String(cleaned.dropFirst(8).prefix(2))
        } else {
            cano = cleaned
            acntPrdtCd = "01"
        }

        let trID = isMock ? "VTTC8434R" : "TTTC8434R"

        var components = URLComponents(
            string: "\(baseURL)/uapi/domestic-stock/v1/trading/inquire-balance"
        )!
        components.queryItems = [
            URLQueryItem(name: "CANO",                    value: cano),
            URLQueryItem(name: "ACNT_PRDT_CD",            value: acntPrdtCd),
            URLQueryItem(name: "AFHR_FLPR_YN",            value: "N"),
            URLQueryItem(name: "OFL_YN",                  value: ""),
            URLQueryItem(name: "INQR_DVSN",               value: "02"),
            URLQueryItem(name: "UNPR_DVSN",               value: "01"),
            URLQueryItem(name: "FUND_STTL_ICLD_YN",       value: "N"),
            URLQueryItem(name: "FNCG_AMT_AUTO_RDPT_YN",   value: "N"),
            URLQueryItem(name: "PRCS_DVSN",               value: "01"),
            URLQueryItem(name: "CTX_AREA_FK100",          value: ""),
            URLQueryItem(name: "CTX_AREA_NK100",          value: "")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(creds.appKey,    forHTTPHeaderField: "appkey")
        request.setValue(creds.appSecret, forHTTPHeaderField: "appsecret")
        request.setValue(trID,            forHTTPHeaderField: "tr_id")
        request.setValue("P",             forHTTPHeaderField: "custtype")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BrokerError.apiError("잔고 조회 실패")
        }

        if let raw = String(data: data, encoding: .utf8) {
            print("[KISAdapter] fetchBalance: \(raw.prefix(500))")
        }

        let decoded = try JSONDecoder().decode(KISBalanceResponse.self, from: data)
        guard decoded.rtCd == "0" else {
            throw BrokerError.apiError(decoded.msg1 ?? "잔고 조회 오류")
        }

        return (decoded.output1 ?? []).compactMap { item -> PortfolioItem? in
            guard let qty = Int(item.hldgQty ?? "0"), qty > 0 else { return nil }
            let symbol = item.pdno ?? ""
            guard !symbol.isEmpty else { return nil }
            // pchs_avg_pric은 소수점 포함 문자열 ("85200.00")
            let avgPrice = Int(Double(item.pchsAvgPric ?? "0") ?? 0)
            return PortfolioItem(id: nil, symbol: symbol, name: item.prdtName ?? symbol,
                                 averagePrice: avgPrice, quantity: qty)
        }
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

private struct KISBalanceResponse: Decodable {
    let rtCd: String
    let msg1: String?
    let output1: [KISBalanceItem]?

    enum CodingKeys: String, CodingKey {
        case rtCd = "rt_cd"
        case msg1
        case output1
    }
}

private struct KISBalanceItem: Decodable {
    let pdno: String?
    let prdtName: String?
    let pchsAvgPric: String?
    let hldgQty: String?

    enum CodingKeys: String, CodingKey {
        case pdno        = "pdno"
        case prdtName    = "prdt_name"
        case pchsAvgPric = "pchs_avg_pric"
        case hldgQty     = "hldg_qty"
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
