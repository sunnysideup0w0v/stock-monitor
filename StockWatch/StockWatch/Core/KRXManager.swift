import Foundation

/// KRX 전종목 시세·시가총액 수집 관리자.
/// - API 키 있음: KRX OpenAPI (data-dbg.krx.co.kr) — 공식 API, PER/PBR 미제공
/// - API 키 없음: 네이버 증권 모바일 API (m.stock.naver.com) — 인증 불필요 폴백
@MainActor
final class KRXManager {
    static let shared = KRXManager()
    private init() {}

    private(set) var isFetching = false
    private var timer: Timer?

    // MARK: - 시작

    func start() {
        Task { await fetchIfNeeded() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { await KRXManager.shared.fetchIfNeeded() }
        }
    }

    // MARK: - 갱신 필요 여부

    func fetchIfNeeded() async {
        guard !isFetching else { return }
        let target = lastTradingDate()
        if let last = try? DatabaseManager.shared.stockUniverseLastUpdated() {
            if dateString(from: last) == target { return }
        }
        await fetchAndStore()
    }

    // MARK: - 데이터 fetch + 저장

    func fetchAndStore() async {
        guard !isFetching else { return }
        isFetching = true
        defer {
            isFetching = false
            NotificationCenter.default.post(name: .krxDataUpdated, object: nil)
        }

        let date = lastTradingDate()
        let apiKey = KeychainHelper.load(account: "krx.apiKey") ?? ""

        let items: [StockUniverseItem]
        if !apiKey.isEmpty {
            items = await fetchFromKRXOpenAPI(date: date, apiKey: apiKey)
        } else {
            items = await fetchFromNaver()
        }

        guard !items.isEmpty else { return }
        try? DatabaseManager.shared.replaceStockUniverse(items)
    }

    // MARK: - KRX OpenAPI (공식 — API 키 필요)

    private func fetchFromKRXOpenAPI(date: String, apiKey: String) async -> [StockUniverseItem] {
        async let kospi  = fetchKRXMarket(path: "/sto/stk_bydd_trd",  date: date, apiKey: apiKey, market: "KOSPI")
        async let kosdaq = fetchKRXMarket(path: "/sto/ksq_bydd_trd", date: date, apiKey: apiKey, market: "KOSDAQ")
        let combined = await kospi + kosdaq
        return combined
    }

    private func fetchKRXMarket(path: String, date: String, apiKey: String, market: String) async -> [StockUniverseItem] {
        var components = URLComponents(string: "http://data-dbg.krx.co.kr/svc/apis\(path)")!
        components.queryItems = [URLQueryItem(name: "basDd", value: date)]
        guard let url = components.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "AUTH_KEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let data = try? await URLSession.shared.data(for: req).0,
              let response = try? JSONDecoder().decode(KRXApiResponse.self, from: data)
        else { return [] }

        let now = Date()
        return response.outBlock1.compactMap { rec in
            let sym = rec.ISU_CD.trimmingCharacters(in: .whitespaces)
            guard sym.count == 6, sym.allSatisfy(\.isNumber) else { return nil }
            let close   = parseKRXInt(rec.TDD_CLSPRC)
            let change  = parseKRXInt(rec.CMPPREVDD_PRC)
            let prevClose = close - change
            let sector: String? = rec.SECT_TP_NM.isEmpty || rec.SECT_TP_NM == "-" ? nil : rec.SECT_TP_NM
            return StockUniverseItem(
                id: nil,
                symbol: sym,
                name: rec.ISU_NM,
                market: market,
                sector: sector,
                close: close,
                open: prevClose,      // 전일 종가 → changeRate 계산용
                high: parseKRXInt(rec.TDD_HGPRC),
                low: parseKRXInt(rec.TDD_LWPRC),
                volume: parseKRXInt(rec.ACC_TRDVOL),
                marketCap: parseKRXInt64(rec.MKTCAP) / 1_000_000,  // 원 → 백만원
                per: nil,
                pbr: nil,
                updatedAt: now
            )
        }
    }

    private func parseKRXInt(_ s: String) -> Int {
        Int(s.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private func parseKRXInt64(_ s: String) -> Int {
        Int(s.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    // MARK: - 네이버 증권 API (폴백 — 인증 불필요)

    private func fetchFromNaver() async -> [StockUniverseItem] {
        async let kospiItems  = fetchAllNaverPages(market: "KOSPI")
        async let kosdaqItems = fetchAllNaverPages(market: "KOSDAQ")

        let combined = await kospiItems + kosdaqItems
        guard !combined.isEmpty else { return [] }

        let now = Date()
        return combined.compactMap { raw in
            let sym = raw.itemCode.trimmingCharacters(in: .whitespaces)
            guard sym.count == 6 else { return nil }
            let prevClose = raw.closeInt - raw.changeInt
            return StockUniverseItem(
                id: nil,
                symbol: sym,
                name: raw.stockName,
                market: raw.stockExchangeType.nameEng,
                sector: nil,
                close: raw.closeInt,
                open: prevClose,
                high: 0,
                low: 0,
                volume: raw.volumeInt,
                marketCap: raw.marketCapMillions,
                per: nil,
                pbr: nil,
                updatedAt: now
            )
        }
    }

    private func fetchAllNaverPages(market: String) async -> [NaverStockItem] {
        guard let (firstItems, totalCount) = await fetchNaverPage(market: market, page: 1) else { return [] }

        var allItems = firstItems
        let totalPages = Int((Double(totalCount) / 100.0).rounded(.up))

        if totalPages > 1 {
            await withTaskGroup(of: [NaverStockItem].self) { group in
                for page in 2...totalPages {
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        return (await self.fetchNaverPage(market: market, page: page))?.0 ?? []
                    }
                }
                for await items in group {
                    allItems.append(contentsOf: items)
                }
            }
        }

        return allItems
    }

    private func fetchNaverPage(market: String, page: Int) async -> (items: [NaverStockItem], total: Int)? {
        let urlStr = "https://m.stock.naver.com/api/stocks/marketValue/\(market)?page=\(page)&pageSize=100"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard let data = try? await URLSession.shared.data(for: req).0,
              let response = try? JSONDecoder().decode(NaverMarketResponse.self, from: data)
        else { return nil }
        return (response.stocks, response.totalCount)
    }

    // MARK: - 날짜 헬퍼

    /// 현재 시각 기준 최근 거래일(YYYYMMDD). 16시 이전 → 전일, 주말 → 직전 금요일.
    func lastTradingDate() -> String {
        let cal = Calendar.current
        var date = Date()
        if cal.component(.hour, from: date) < 16 {
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }
        var weekday = cal.component(.weekday, from: date)
        while weekday == 1 || weekday == 7 {
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
            weekday = cal.component(.weekday, from: date)
        }
        return dateString(from: date)
    }

    private func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    // MARK: - API 소스 정보

    var isUsingOfficialAPI: Bool {
        !(KeychainHelper.load(account: "krx.apiKey") ?? "").isEmpty
    }
}

// MARK: - KRX OpenAPI 응답 모델

private struct KRXApiResponse: Decodable {
    let outBlock1: [KRXDailyRecord]
    enum CodingKeys: String, CodingKey { case outBlock1 = "OutBlock_1" }
}

private struct KRXDailyRecord: Decodable {
    let ISU_CD: String       // 종목코드 (6자리)
    let ISU_NM: String       // 종목명
    let MKT_NM: String       // 시장구분
    let SECT_TP_NM: String   // 소속부 (업종)
    let TDD_CLSPRC: String   // 종가
    let CMPPREVDD_PRC: String // 전일 대비
    let TDD_OPNPRC: String   // 시가
    let TDD_HGPRC: String    // 고가
    let TDD_LWPRC: String    // 저가
    let ACC_TRDVOL: String   // 거래량
    let MKTCAP: String       // 시가총액 (원)
}

// MARK: - 네이버 증권 응답 모델

private struct NaverMarketResponse: Decodable {
    let stocks: [NaverStockItem]
    let totalCount: Int
}

private struct NaverStockItem: Decodable {
    let itemCode: String
    let stockName: String
    let stockExchangeType: NaverExchangeType
    // Naver API는 숫자 값을 JSON 문자열로 반환함
    let closePriceRaw: String
    let compareToPreviousClosePriceRaw: String
    let accumulatedTradingVolumeRaw: String
    let marketValueRaw: String

    var closeInt: Int { Int(closePriceRaw) ?? 0 }
    var changeInt: Int { Int(compareToPreviousClosePriceRaw) ?? 0 }
    var volumeInt: Int { Int(accumulatedTradingVolumeRaw) ?? 0 }
    var marketCapMillions: Int { (Int(marketValueRaw) ?? 0) / 1_000_000 }
}

private struct NaverExchangeType: Decodable {
    let nameEng: String   // "KOSPI" | "KOSDAQ"
}
