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
        let (data, response) = try await URLSession.shared.data(for: request)
        let rawString = String(data: data, encoding: .utf8) ?? ""
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        APILogger.logResponse(tag: "kt00018", status: status, body: rawString)

        if status == 403 {
            throw BrokerError.apiError("잔고 조회 권한이 없습니다. Open API 포털 → 서비스 신청에서 kt00018(잔고조회) 활성화 여부를 확인해주세요.")
        }
        guard status == 200 else {
            throw BrokerError.apiError("잔고 조회 실패 (HTTP \(status))")
        }

        let decoded: KiwoomBalanceResponse
        do {
            decoded = try JSONDecoder().decode(KiwoomBalanceResponse.self, from: data)
        } catch {
            AppLogger.log("KiwoomAdapter 잔고 응답 디코딩 실패 — \(rawString)", level: .error, category: "App")
            throw BrokerError.apiError("잔고 조회 응답을 해석할 수 없습니다.")
        }
        guard decoded.returnCode == 0 else {
            throw BrokerError.apiError(Self.kiwoomErrorMessage(decoded.returnMsg))
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

    func fetchDailyVolumes(symbol: String, days: Int) async throws -> [Int] {
        // TODO: 키움 일별시세 TR 코드 확인 후 구현
        return []
    }

    // MARK: - Error Message

    /// 키움 API return_msg를 사용자 친화적 한국어로 변환한다.
    private static func kiwoomErrorMessage(_ raw: String?) -> String {
        switch raw?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "data missing":
            return "필수 요청 데이터가 누락됐습니다. API 키와 시크릿을 확인해주세요."
        case "invalid appkey", "appkey error":
            return "앱 키가 올바르지 않습니다. API 키를 확인해주세요."
        case "invalid secretkey", "secretkey error":
            return "앱 시크릿이 올바르지 않습니다. API 시크릿을 확인해주세요."
        case "invalid token", "token error":
            return "토큰이 유효하지 않습니다. 다시 로그인해주세요."
        case "expired token":
            return "토큰이 만료됐습니다. 다시 로그인해주세요."
        case "quota exceeded", "limit exceeded":
            return "API 호출 한도를 초과했습니다. 잠시 후 다시 시도해주세요."
        default:
            return raw ?? "토큰 발급 오류가 발생했습니다."
        }
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

        let tr: KiwoomTokenResponse
        do {
            tr = try JSONDecoder().decode(KiwoomTokenResponse.self, from: data)
        } catch {
            AppLogger.log("KiwoomAdapter 토큰 응답 디코딩 실패 — \(rawString)", level: .error, category: "App")
            throw BrokerError.apiError("API 응답을 해석할 수 없습니다. API 키와 시크릿을 확인해주세요.")
        }

        guard tr.returnCode == 0 else {
            throw BrokerError.apiError(Self.kiwoomErrorMessage(tr.returnMsg))
        }

        guard let token = tr.token else {
            AppLogger.log("KiwoomAdapter 토큰 필드 없음 — \(rawString)", level: .error, category: "App")
            throw BrokerError.apiError("토큰 발급 응답에 토큰이 없습니다. API 키를 확인해주세요.")
        }
        cachedToken = token

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
    let token: String?      // 오류 응답에는 token 필드가 없으므로 optional
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
