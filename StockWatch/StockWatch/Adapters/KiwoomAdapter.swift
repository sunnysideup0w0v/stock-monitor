import Foundation

actor KiwoomAdapter: BrokerAdapter {
    nonisolated let brokerName = "키움증권"

    private let isMock: Bool
    private var credentials: BrokerCredentials?
    private var cachedToken: String?
    private var tokenExpiry: Date?

    private var baseURL: String {
        isMock ? "https://mockapi.kiwoom.com" : "https://api.kiwoom.com"
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
        try await fetchQuote(symbol: symbol, retryOnUnauthorized: true)
    }

    private func fetchQuote(symbol: String, retryOnUnauthorized: Bool) async throws -> StockQuote {
        let token = try await validToken()

        let url = URL(string: "\(baseURL)/api/dostk/stkinfo")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue("ka10001", forHTTPHeaderField: "api-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["stk_cd": symbol])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BrokerError.apiError("응답 오류") }

        if http.statusCode == 401 {
            guard retryOnUnauthorized else { throw BrokerError.tokenExpired }
            cachedToken = nil; tokenExpiry = nil
            try await issueToken()
            return try await fetchQuote(symbol: symbol, retryOnUnauthorized: false)
        }

        let rawString = String(data: data, encoding: .utf8) ?? ""
        APILogger.logResponse(tag: "ka10001", status: http.statusCode, body: rawString)
        guard http.statusCode == 200 else { throw BrokerError.apiError("HTTP \(http.statusCode)") }

        // 응답이 output 래퍼 없이 flat 구조: { "stk_nm": "...", "cur_prc": "-270500", ..., "return_code": 0 }
        let decoded = try JSONDecoder().decode(KiwoomQuoteResponse.self, from: data)
        guard decoded.returnCode == 0 else {
            throw BrokerError.apiError(decoded.returnMsg ?? "시세 조회 실패")
        }

        // cur_prc: "+270500" / "-270500" → 숫자만 추출해 절대값 사용
        let price = Int((decoded.curPrc ?? "0").filter { $0.isNumber }) ?? 0
        guard price > 0 else { throw BrokerError.symbolNotFound(symbol) }

        // pred_pre / flu_rt: 이미 부호 포함 → 직접 파싱
        let changeAmount = Int(decoded.predPre ?? "0") ?? 0
        let changeRate   = Double(decoded.fluRt ?? "0") ?? 0.0

        return StockQuote(
            symbol: symbol,
            name: decoded.stkNm ?? symbol,
            price: price,
            changeAmount: changeAmount,
            changeRate: changeRate,
            volume: Int((decoded.trdeQty ?? "0").filter { $0.isNumber }) ?? 0,
            timestamp: Date()
        )
    }

    func fetchPortfolio() async throws -> [PortfolioItem] {
        let token = try await validToken()

        let url = URL(string: "\(baseURL)/api/dostk/acnt")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue("kt00018", forHTTPHeaderField: "api-id")

        // qry_tp: "2" = 개별, dmst_stex_tp: "KRX" — 계좌번호는 토큰에 귀속
        let body: [String: Any] = ["qry_tp": "2", "dmst_stex_tp": "KRX"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        APILogger.logRequest(tag: "kt00018", url: url.absoluteString, body: "qry_tp=2,dmst_stex_tp=KRX")

        let (data, response) = try await URLSession.shared.data(for: request)
        let rawString = String(data: data, encoding: .utf8) ?? ""
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        APILogger.logResponse(tag: "kt00018", status: status, body: rawString)

        guard status == 200 else {
            throw BrokerError.apiError("잔고 조회 실패 (HTTP \(status)) — logs/api-*.log 확인")
        }

        let decoded = try JSONDecoder().decode(KiwoomBalanceResponse.self, from: data)
        guard decoded.returnCode == 0 else {
            throw BrokerError.apiError(decoded.returnMsg ?? "잔고 조회 오류")
        }

        return (decoded.output ?? []).compactMap { item -> PortfolioItem? in
            guard let qty = Int((item.rmndQty ?? "0").filter { $0.isNumber }), qty > 0 else { return nil }
            let symbol = item.stkCd ?? ""
            guard !symbol.isEmpty else { return nil }
            let avgPrice = Int(Double((item.purPric ?? "0").filter { $0.isNumber || $0 == "." }) ?? 0)
            return PortfolioItem(id: nil, symbol: symbol, name: item.stkNm ?? symbol,
                                 averagePrice: avgPrice, quantity: qty)
        }
    }

    func fetchNews(symbol: String) async throws -> [NewsItem] { return [] }

    func fetchDailyVolumes(symbol: String, days: Int) async throws -> [Int] {
        // TODO: 키움 일별시세 TR 코드 확인 후 구현
        return []
    }

    // MARK: - Token Management

    private func validToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry { return token }
        try await issueToken()
        guard let token = cachedToken else { throw BrokerError.tokenExpired }
        return token
    }

    private func issueToken() async throws {
        guard let creds = credentials else { throw BrokerError.notConnected }

        let url = URL(string: "\(baseURL)/oauth2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "content-type")

        // 키움은 "secretkey" (KIS는 "appsecret")
        let body: [String: String] = [
            "grant_type": "client_credentials",
            "appkey": creds.appKey,
            "secretkey": creds.appSecret
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let rawString = String(data: data, encoding: .utf8) ?? ""
        APILogger.logResponse(tag: "token", status: status, body: rawString)

        guard status == 200 else {
            throw BrokerError.apiError("토큰 발급 실패 (HTTP \(status)) — API 키를 확인해주세요")
        }

        let tr = try JSONDecoder().decode(KiwoomTokenResponse.self, from: data)
        guard tr.returnCode == 0 else {
            throw BrokerError.apiError(tr.returnMsg ?? "토큰 발급 오류")
        }

        cachedToken = tr.token

        // expires_dt: "20251231235959" (YYYYMMDDHHMMSS) → Date, 5분 전 갱신
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        if let expStr = tr.expiresDt, let expDate = df.date(from: expStr) {
            tokenExpiry = expDate.addingTimeInterval(-300)
        } else {
            tokenExpiry = Date().addingTimeInterval(86400 - 300)
        }
    }
}

// MARK: - Response Models

private struct KiwoomTokenResponse: Decodable {
    let token: String
    let expiresDt: String?
    let tokenType: String?
    let returnCode: Int
    let returnMsg: String?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresDt  = "expires_dt"
        case tokenType  = "token_type"
        case returnCode = "return_code"
        case returnMsg  = "return_msg"
    }
}

// ka10001 응답은 output 래퍼 없이 모든 필드가 최상위에 flat하게 위치
private struct KiwoomQuoteResponse: Decodable {
    let returnCode: Int
    let returnMsg: String?
    let stkNm: String?    // 종목명
    let curPrc: String?   // 현재가 (부호 포함: "+270500" / "-270500")
    let predPre: String?  // 전일대비 (부호 포함: "-25500")
    let fluRt: String?    // 등락률 (부호 포함: "-8.61")
    let trdeQty: String?  // 거래량

    enum CodingKeys: String, CodingKey {
        case returnCode = "return_code"
        case returnMsg  = "return_msg"
        case stkNm      = "stk_nm"
        case curPrc     = "cur_prc"
        case predPre    = "pred_pre"
        case fluRt      = "flu_rt"
        case trdeQty    = "trde_qty"
    }
}

private struct KiwoomBalanceResponse: Decodable {
    let returnCode: Int
    let returnMsg: String?
    let output: [KiwoomBalanceItem]?

    enum CodingKeys: String, CodingKey {
        case returnCode = "return_code"
        case returnMsg  = "return_msg"
        case output     = "acnt_evlt_remn_indv_tot"
    }
}

private struct KiwoomBalanceItem: Decodable {
    let stkCd: String?   // 종목코드
    let stkNm: String?   // 종목명
    let rmndQty: String? // 보유수량
    let purPric: String? // 매입가

    enum CodingKeys: String, CodingKey {
        case stkCd   = "stk_cd"
        case stkNm   = "stk_nm"
        case rmndQty = "rmnd_qty"
        case purPric = "pur_pric"
    }
}
