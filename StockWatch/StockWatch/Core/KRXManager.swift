import Foundation

/// 네이버 증권 모바일 API(m.stock.naver.com)에서 전종목 시세·시가총액을 수집한다.
/// 별도 인증 불필요. 평일 16:00 이후 마지막 거래일 데이터를 자동 갱신.
/// (KRX data.krx.co.kr는 세션 인증 필요로 변경되어 Naver API로 교체)
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

        async let kospiItems  = fetchAllPages(market: "KOSPI")
        async let kosdaqItems = fetchAllPages(market: "KOSDAQ")

        let combined = await kospiItems + kosdaqItems
        guard !combined.isEmpty else { return }

        let now = Date()
        let items: [StockUniverseItem] = combined.compactMap { raw in
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
                open: prevClose,          // 전일 종가를 open에 저장 → changeRate 계산에 활용
                high: 0,
                low: 0,
                volume: raw.volumeInt,
                marketCap: raw.marketCapMillions,   // 원 → 백만원
                per: nil,
                pbr: nil,
                updatedAt: now
            )
        }

        guard !items.isEmpty else { return }
        try? DatabaseManager.shared.replaceStockUniverse(items)
    }

    // MARK: - Naver API 페이지 수집

    private func fetchAllPages(market: String) async -> [NaverStockItem] {
        guard let (firstItems, totalCount) = await fetchPage(market: market, page: 1) else { return [] }

        var allItems = firstItems
        let totalPages = Int((Double(totalCount) / 100.0).rounded(.up))

        if totalPages > 1 {
            await withTaskGroup(of: [NaverStockItem].self) { group in
                for page in 2...totalPages {
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        return (await self.fetchPage(market: market, page: page))?.0 ?? []
                    }
                }
                for await items in group {
                    allItems.append(contentsOf: items)
                }
            }
        }

        return allItems
    }

    private func fetchPage(market: String, page: Int) async -> (items: [NaverStockItem], total: Int)? {
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

    /// 현재 시각 기준으로 가장 최근 거래일(YYYYMMDD)을 반환한다.
    /// 16:00 이전이면 전 거래일, 주말은 직전 금요일로 처리한다.
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
