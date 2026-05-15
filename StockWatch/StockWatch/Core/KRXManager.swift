import Foundation

/// KRX 공공 데이터 포털(data.krx.co.kr)에서 전종목 일별 시세·PER/PBR을 수집한다.
/// 별도 API 키 불필요. 평일 16:00 이후 마지막 거래일 데이터를 자동 갱신.
@MainActor
final class KRXManager {
    static let shared = KRXManager()
    private init() {}

    private(set) var isFetching = false
    private var timer: Timer?

    private let base = "https://data.krx.co.kr/comm/bldAttendant/getJsonData.cmd"

    // MARK: - 시작

    func start() {
        Task { await fetchIfNeeded() }
        // 1시간마다 갱신 필요 여부 확인
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { await KRXManager.shared.fetchIfNeeded() }
        }
    }

    // MARK: - 갱신 필요 여부

    func fetchIfNeeded() async {
        guard !isFetching else { return }
        let target = lastTradingDate()
        if let last = try? DatabaseManager.shared.stockUniverseLastUpdated() {
            let fmt = krxDateFormatter()
            if fmt.string(from: last) == target { return }
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

        async let kospiResult  = fetchPrices(market: "STK", date: date)
        async let kosdaqResult = fetchPrices(market: "KSQ", date: date)
        async let kospiPer     = fetchFinancial(market: "STK", date: date)
        async let kosdaqPer    = fetchFinancial(market: "KSQ", date: date)

        guard let kospi  = await kospiResult,
              let kosdaq = await kosdaqResult else { return }

        let perMap = buildPerMap(await kospiPer, await kosdaqPer)
        let now = Date()

        var items: [StockUniverseItem] = []
        for raw in (kospi + kosdaq) {
            let sym = raw.ISU_SRT_CD.trimmingCharacters(in: .whitespaces)
            guard !sym.isEmpty, sym.count == 6 else { continue }
            let fin = perMap[sym]
            items.append(StockUniverseItem(
                id: nil,
                symbol: sym,
                name: raw.ISU_ABBRV.trimmingCharacters(in: .whitespaces),
                market: raw.MKT_NM ?? "",
                sector: raw.SECT_TP_NM,
                close: parseInt(raw.TDD_CLSPRC),
                open: parseInt(raw.TDD_OPNPRC),
                high: parseInt(raw.TDD_HGPRC),
                low: parseInt(raw.TDD_LWPRC),
                volume: parseInt(raw.ACC_TRDVOL),
                marketCap: parseInt(raw.MKTCAP),
                per: fin?.per,
                pbr: fin?.pbr,
                updatedAt: now
            ))
        }

        guard !items.isEmpty else { return }
        try? DatabaseManager.shared.replaceStockUniverse(items)
    }

    // MARK: - API 호출

    private func fetchPrices(market: String, date: String) async -> [KRXPriceItem]? {
        let body = "bld=dbms/MDC/STAT/standard/MDCSTAT01501" +
                   "&locale=ko_KR&mktId=\(market)&trdDd=\(date)" +
                   "&share=1&money=1&csvxls_isNo=false"
        guard let data = await post(body: body) else { return nil }
        return (try? JSONDecoder().decode(KRXPriceResponse.self, from: data))?.OutBlock_1
    }

    private func fetchFinancial(market: String, date: String) async -> [KRXFinancialItem]? {
        let body = "bld=dbms/MDC/STAT/standard/MDCSTAT03901" +
                   "&locale=ko_KR&mktId=\(market)&trdDd=\(date)" +
                   "&share=1&money=1&csvxls_isNo=false"
        guard let data = await post(body: body) else { return nil }
        return (try? JSONDecoder().decode(KRXFinancialResponse.self, from: data))?.OutBlock_1
    }

    private func post(body: String) async -> Data? {
        guard let url = URL(string: base) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("https://data.krx.co.kr/", forHTTPHeaderField: "Referer")
        req.httpBody = body.data(using: .utf8)
        return try? await URLSession.shared.data(for: req).0
    }

    // MARK: - 헬퍼

    private func buildPerMap(_ kospi: [KRXFinancialItem]?, _ kosdaq: [KRXFinancialItem]?) -> [String: (per: Double?, pbr: Double?)] {
        var map: [String: (per: Double?, pbr: Double?)] = [:]
        for item in ((kospi ?? []) + (kosdaq ?? [])) {
            map[item.ISU_SRT_CD.trimmingCharacters(in: .whitespaces)] = (
                per: parseDouble(item.PER),
                pbr: parseDouble(item.PBR)
            )
        }
        return map
    }

    /// 현재 시각 기준으로 가장 최근 거래일(YYYYMMDD)을 반환한다.
    /// 16:00 이전이면 전 거래일, 주말은 직전 금요일로 처리한다.
    func lastTradingDate() -> String {
        let cal = Calendar.current
        var date = Date()
        let hour = cal.component(.hour, from: date)

        if hour < 16 {
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }

        var weekday = cal.component(.weekday, from: date)
        while weekday == 1 || weekday == 7 {
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
            weekday = cal.component(.weekday, from: date)
        }

        return krxDateFormatter().string(from: date)
    }

    private func krxDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    private func parseInt(_ str: String?) -> Int {
        guard let s = str else { return 0 }
        return Int(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private func parseDouble(_ str: String?) -> Double? {
        guard let s = str?.trimmingCharacters(in: .whitespaces), s != "-", !s.isEmpty else { return nil }
        return Double(s.replacingOccurrences(of: ",", with: ""))
    }
}

// MARK: - KRX 응답 모델

private struct KRXPriceResponse: Decodable {
    let OutBlock_1: [KRXPriceItem]
}

private struct KRXPriceItem: Decodable {
    let ISU_SRT_CD: String
    let ISU_ABBRV: String
    let MKT_NM: String?
    let SECT_TP_NM: String?
    let TDD_CLSPRC: String?
    let TDD_OPNPRC: String?
    let TDD_HGPRC: String?
    let TDD_LWPRC: String?
    let ACC_TRDVOL: String?
    let MKTCAP: String?
}

private struct KRXFinancialResponse: Decodable {
    let OutBlock_1: [KRXFinancialItem]
}

private struct KRXFinancialItem: Decodable {
    let ISU_SRT_CD: String
    let PER: String?
    let PBR: String?
}
