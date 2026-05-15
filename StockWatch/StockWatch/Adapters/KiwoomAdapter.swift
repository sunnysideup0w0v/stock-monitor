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

        let url = URL(string: "\(baseURL)/api/dostk/info")!
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

        if let raw = String(data: data, encoding: .utf8) {
            print("[KiwoomAdapter] fetchQuote(\(symbol)): \(raw.prefix(500))")
        }
        guard http.statusCode == 200 else { throw BrokerError.apiError("HTTP \(http.statusCode)") }

        let decoded = try JSONDecoder().decode(KiwoomQuoteResponse.self, from: data)
        guard decoded.returnCode == 0, let output = decoded.output else {
            throw BrokerError.apiError(decoded.returnMsg ?? "시세 조회 실패")
        }

        let price = Int((output.curPrc ?? "0").filter { $0.isNumber }) ?? 0
        guard price > 0 else { throw BrokerError.symbolNotFound(symbol) }

        // flu_smbol: 1=상한 2=상승 3=보합 4=하락 5=하한
        let isNegative = output.fluSmbol == "4" || output.fluSmbol == "5"
        let absChange = Int((output.predPre ?? "0").filter { $0.isNumber }) ?? 0
        let changeAmount = isNegative ? -absChange : absChange
        let absRate = Double((output.fluRt ?? "0").filter { $0.isNumber || $0 == "." }) ?? 0.0
        let changeRate = isNegative ? -absRate : absRate

        return StockQuote(
            symbol: symbol,
            name: output.stkNm ?? symbol,
            price: price,
            changeAmount: changeAmount,
            changeRate: changeRate,
            volume: Int((output.accTrdvol ?? "0").filter { $0.isNumber }) ?? 0,
            timestamp: Date()
        )
    }

    func fetchPortfolio() async throws -> [PortfolioItem] {
        let token = try await validToken()
        guard let creds = credentials else { throw BrokerError.notConnected }
        guard let acctNo = creds.accountNumber, !acctNo.isEmpty else {
            throw BrokerError.apiError("계좌번호를 설정해 주세요")
        }

        let url = URL(string: "\(baseURL)/api/dostk/account")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue("kt00018", forHTTPHeaderField: "api-id")

        // kt00018 계좌평가잔고내역요청 — 파라미터명은 공식 문서 확인 후 보정 필요
        let body: [String: Any] = ["acnt_no": acctNo, "qry_tp": "0"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let raw = String(data: data, encoding: .utf8) {
            print("[KiwoomAdapter] fetchPortfolio: \(raw.prefix(1000))")
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BrokerError.apiError("잔고 조회 실패")
        }

        let decoded = try JSONDecoder().decode(KiwoomBalanceResponse.self, from: data)
        guard decoded.returnCode == 0 else {
            throw BrokerError.apiError(decoded.returnMsg ?? "잔고 조회 오류")
        }

        return (decoded.output ?? []).compactMap { item -> PortfolioItem? in
            guard let qty = Int((item.holdQty ?? "0").filter { $0.isNumber }), qty > 0 else { return nil }
            let symbol = item.stkCd ?? ""
            guard !symbol.isEmpty else { return nil }
            let avgPrice = Int(Double((item.avgPrc ?? "0").filter { $0.isNumber || $0 == "." }) ?? 0)
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
        if let raw = String(data: data, encoding: .utf8) {
            print("[KiwoomAdapter] token response (\(status)): \(raw.prefix(300))")
        }
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

private struct KiwoomQuoteResponse: Decodable {
    let returnCode: Int
    let returnMsg: String?
    let output: KiwoomQuoteOutput?

    enum CodingKeys: String, CodingKey {
        case returnCode = "return_code"
        case returnMsg  = "return_msg"
        case output
    }
}

private struct KiwoomQuoteOutput: Decodable {
    let stkNm: String?     // 종목명
    let curPrc: String?    // 현재가
    let fluSmbol: String?  // 등락기호: 1=상한 2=상승 3=보합 4=하락 5=하한
    let predPre: String?   // 전일대비 (절댓값)
    let fluRt: String?     // 등락률 (절댓값)
    let accTrdvol: String? // 누적거래량

    enum CodingKeys: String, CodingKey {
        case stkNm     = "stk_nm"
        case curPrc    = "cur_prc"
        case fluSmbol  = "flu_smbol"
        case predPre   = "pred_pre"
        case fluRt     = "flu_rt"
        case accTrdvol = "acc_trdvol"
    }
}

private struct KiwoomBalanceResponse: Decodable {
    let returnCode: Int
    let returnMsg: String?
    let output: [KiwoomBalanceItem]?

    enum CodingKeys: String, CodingKey {
        case returnCode = "return_code"
        case returnMsg  = "return_msg"
        case output
    }
}

// 잔고 필드명은 kt00018 공식 문서 확인 후 보정 필요
private struct KiwoomBalanceItem: Decodable {
    let stkCd: String?   // 종목코드
    let stkNm: String?   // 종목명
    let holdQty: String? // 보유수량
    let avgPrc: String?  // 평균매입가

    enum CodingKeys: String, CodingKey {
        case stkCd   = "stk_cd"
        case stkNm   = "stk_nm"
        case holdQty = "hold_qty"
        case avgPrc  = "avg_prc"
    }
}
