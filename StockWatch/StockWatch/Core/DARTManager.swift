import Foundation

@MainActor
final class DARTManager {
    static let shared = DARTManager()
    private init() {}

    private var pollingTask: Task<Void, Never>?
    private var corpCodeCache: [String: String] = [:]

    // MARK: - Public Interface

    var isConfigured: Bool {
        let key = KeychainHelper.load(account: KeychainKey.dartApiKey) ?? ""
        return !key.isEmpty
    }

    func start(symbols: [String]) {
        guard let apiKey = KeychainHelper.load(account: KeychainKey.dartApiKey),
              !apiKey.isEmpty, !symbols.isEmpty else { return }
        stop()
        pollingTask = Task {
            while !Task.isCancelled {
                await poll(symbols: symbols, apiKey: apiKey)
                try? await Task.sleep(for: .seconds(300)) // 5분
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Polling

    private func poll(symbols: [String], apiKey: String) async {
        for symbol in symbols {
            guard !Task.isCancelled else { return }
            await checkDisclosures(symbol: symbol, apiKey: apiKey)
        }
    }

    private func checkDisclosures(symbol: String, apiKey: String) async {
        do {
            let corpCode: String
            if let cached = corpCodeCache[symbol] {
                corpCode = cached
            } else {
                corpCode = try await fetchCorpCode(stockCode: symbol, apiKey: apiKey)
                corpCodeCache[symbol] = corpCode
            }

            let since = lastCheckDate(for: symbol)
            let disclosures = try await fetchDisclosures(corpCode: corpCode, apiKey: apiKey, since: since)

            let seenKey = UserDefaultsKey.dartSeen(symbol)
            var seenIds = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
            let newDisclosures = disclosures.filter { !seenIds.contains($0.rceptNo) }
            let filterTypes = UserDefaults.standard.stringArray(forKey: UserDefaultsKey.dartFilterTypes) ?? []

            for disclosure in newDisclosures {
                let typeOK = filterTypes.isEmpty || filterTypes.contains(disclosure.disclosureType)
                let timeOK = !AlertEvaluator.marketHoursOnly || AlertEvaluator.isWithinMarketHours()

                if !typeOK {
                    // 사용자가 원하지 않는 공시 종류 → 즉시 seen 처리 (다시 알릴 필요 없음)
                    seenIds.insert(disclosure.rceptNo)
                    continue
                }
                if !timeOK {
                    // 장 시간 외 → seen 미처리, 다음 폴링에서 재시도 (장 열리면 알림 발송)
                    continue
                }

                let dartURL = "https://dart.fss.or.kr/dsaf001/main.do?rcpNo=\(disclosure.rceptNo)"
                NotificationManager.shared.send(
                    title: "[\(disclosure.corpName)] 공시",
                    body: disclosure.reportName,
                    symbol: symbol,
                    urlString: dartURL
                )
                var history = AlertHistory(
                    id: nil,
                    symbol: disclosure.stockCode.isEmpty ? symbol : disclosure.stockCode,
                    triggerType: .dartDisclosure,
                    message: disclosure.reportName,
                    triggeredAt: Date(),
                    metadata: disclosure.rceptNo
                )
                try? DatabaseManager.shared.insert(&history)
                seenIds.insert(disclosure.rceptNo)
            }

            // 최대 500개로 제한해 UserDefaults 비대화 방지
            let trimmed = Array(seenIds.prefix(500))
            UserDefaults.standard.set(trimmed, forKey: seenKey)
            updateLastCheckDate(for: symbol)

        } catch {
            print("[DART] \(symbol) 공시 조회 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - API

    private func fetchCorpCode(stockCode: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://opendart.fss.or.kr/api/company.json?crtfc_key=\(apiKey)&stock_code=\(stockCode)") else {
            throw DARTError.apiError("잘못된 URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DARTError.apiError("회사 코드 조회 실패")
        }
        struct CompanyResponse: Decodable {
            let status: String
            let corpCode: String?
            enum CodingKeys: String, CodingKey {
                case status
                case corpCode = "corp_code"
            }
        }
        let decoded = try JSONDecoder().decode(CompanyResponse.self, from: data)
        guard decoded.status == "000", let corpCode = decoded.corpCode else {
            throw DARTError.notFound(stockCode)
        }
        return corpCode
    }

    private func fetchDisclosures(corpCode: String, apiKey: String, since: String) async throws -> [DARTDisclosure] {
        var components = URLComponents(string: "https://opendart.fss.or.kr/api/list.json")!
        components.queryItems = [
            URLQueryItem(name: "crtfc_key",  value: apiKey),
            URLQueryItem(name: "corp_code",  value: corpCode),
            URLQueryItem(name: "bgn_de",     value: since),
            URLQueryItem(name: "end_de",     value: todayString()),
            URLQueryItem(name: "page_count", value: "20")
        ]
        guard let url = components.url else { throw DARTError.apiError("잘못된 URL") }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DARTError.apiError("공시 목록 조회 실패")
        }

        struct ListResponse: Decodable {
            let status: String
            let list: [Item]?
            struct Item: Decodable {
                let rceptNo: String
                let corpName: String
                let stockCode: String?
                let reportNm: String
                let rceptDt: String
                let pblntfTy: String?
                enum CodingKeys: String, CodingKey {
                    case rceptNo   = "rcept_no"
                    case corpName  = "corp_name"
                    case stockCode = "stock_code"
                    case reportNm  = "report_nm"
                    case rceptDt   = "rcept_dt"
                    case pblntfTy  = "pblntf_ty"
                }
            }
        }

        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        // status "010" = 데이터 없음 (정상)
        guard decoded.status == "000" || decoded.status == "010" else {
            throw DARTError.apiError("DART 오류 \(decoded.status)")
        }

        return (decoded.list ?? []).map {
            DARTDisclosure(
                rceptNo: $0.rceptNo,
                corpName: $0.corpName,
                stockCode: $0.stockCode ?? "",
                reportName: $0.reportNm,
                receivedDate: $0.rceptDt,
                disclosureType: $0.pblntfTy ?? ""
            )
        }
    }

    // MARK: - Helpers

    private func lastCheckDate(for symbol: String) -> String {
        UserDefaults.standard.string(forKey: UserDefaultsKey.dartLastCheck(symbol)) ?? todayString()
    }

    private func updateLastCheckDate(for symbol: String) {
        UserDefaults.standard.set(todayString(), forKey: UserDefaultsKey.dartLastCheck(symbol))
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        return fmt.string(from: Date())
    }
}

enum DARTError: LocalizedError {
    case apiError(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg):  return "DART API 오류: \(msg)"
        case .notFound(let code): return "DART에서 종목코드 \(code)를 찾을 수 없습니다"
        }
    }
}
