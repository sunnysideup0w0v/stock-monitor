import Foundation

@MainActor
final class QuoteManager: ObservableObject {
    static let shared = QuoteManager()

    @Published private(set) var quotes: [String: StockQuote] = [:]
    @Published private(set) var connectionState: ConnectionState = .disconnected
    /// symbol → 최근 5일 평균 거래량 캐시
    private(set) var avgVolumes: [String: Int] = [:]

    enum ConnectionState {
        case connected, disconnected, error
    }

    // key = accountId ("KIS-XXXX", "KIWOOM-XXXX") 또는 "__primary"(Mock 폴백)
    private var adapters: [String: any BrokerAdapter] = [:]
    private var pollingTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private(set) var currentSymbols: [String] = []
    private var disconnectNotified = false

    static var disconnectAlertEnabled: Bool {
        get { UserDefaults.standard.object(forKey: UserDefaultsKey.disconnectAlert) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.disconnectAlert) }
    }

    private init() {}

    /// 실제 브로커 어댑터 추가. Mock 폴백이 있으면 제거하고 실 어댑터로 교체.
    func addAdapter(id: String, adapter: any BrokerAdapter) {
        adapters.removeValue(forKey: "__primary")
        adapters[id] = adapter
        consecutiveFailures = 0
        disconnectNotified = false
    }

    /// 특정 브로커 어댑터 제거. 남은 어댑터가 없으면 Mock으로 폴백.
    func removeAdapter(id: String) {
        adapters.removeValue(forKey: id)
        if adapters.isEmpty { setAdapter(MockBrokerAdapter()) }
    }

    /// Mock 전용 단일 어댑터 설정 (로그아웃 폴백 / 앱 초기화).
    func setAdapter(_ adapter: any BrokerAdapter) {
        adapters = ["__primary": adapter]
        consecutiveFailures = 0
        disconnectNotified = false
        connectionState = .disconnected
    }

    func reconnect() {
        guard !currentSymbols.isEmpty else { return }
        startPolling(symbols: currentSymbols)
    }

    func startPolling(symbols: [String]) {
        currentSymbols = symbols
        stopPolling()
        guard !symbols.isEmpty else { return }
        refreshAverageVolumes(symbols: symbols)
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchAll(symbols: symbols)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func refreshAverageVolumes(symbols: [String]) {
        // 일별 거래량은 아무 실 어댑터에서나 동일한 결과 → 첫 번째 실 어댑터 사용
        let adapter = adapters.first(where: { $0.key != "__primary" })?.value ?? adapters["__primary"]
        guard let adapter, !symbols.isEmpty else { return }
        Task {
            for symbol in symbols {
                let volumes = (try? await adapter.fetchDailyVolumes(symbol: symbol, days: 5)) ?? []
                guard !volumes.isEmpty else { continue }
                avgVolumes[symbol] = volumes.reduce(0, +) / volumes.count
            }
        }
    }

    func startRealtime(credentials: BrokerCredentials, isMock: Bool) {
        let manager = RealtimeQuoteManager.shared
        Task {
            await manager.setOnUpdate { quote in
                await MainActor.run {
                    QuoteManager.shared.updateFromRealtime(quote: quote)
                }
            }
            await manager.start(credentials: credentials, isMock: isMock, symbols: currentSymbols)
        }
    }

    func stopRealtime() {
        Task { await RealtimeQuoteManager.shared.stop() }
    }

    func updateFromRealtime(quote: StockQuote) {
        quotes[quote.symbol] = quote
        consecutiveFailures = 0
        connectionState = .connected
        AlertEvaluator.shared.evaluate(quotes: quotes)
    }

    /// 특정 브로커의 잔고 조회. accountId 미지정 시 첫 번째 실 어댑터 사용.
    func fetchBalance(for accountId: String? = nil) async throws -> [PortfolioItem] {
        if let accountId {
            guard let adapter = adapters[accountId] else { throw BrokerError.notConnected }
            return try await adapter.fetchPortfolio()
        }
        let adapter = adapters.first(where: { $0.key != "__primary" })?.value ?? adapters["__primary"]
        guard let adapter else { throw BrokerError.notConnected }
        return try await adapter.fetchPortfolio()
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func fetchAll(symbols: [String]) async {
        guard !adapters.isEmpty else { return }

        // 실 어댑터 우선, 없으면 mock. 시세는 어떤 브로커든 동일한 한국 주식 시장 데이터.
        // 각 종목마다 어댑터를 순서대로 시도 — 앞 어댑터 실패 시 다음으로 폴백.
        let orderedAdapters = adapters
            .sorted { $0.key == "__primary" ? false : $1.key == "__primary" ? true : $0.key < $1.key }
            .map { $0.value }

        var updated = quotes
        var successCount = 0

        await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in symbols {
                group.addTask {
                    for adapter in orderedAdapters {
                        if let quote = try? await adapter.fetchQuote(symbol: symbol) {
                            return (symbol, quote)
                        }
                    }
                    return (symbol, nil)
                }
            }
            for await (symbol, quote) in group {
                if let quote {
                    updated[symbol] = quote
                    successCount += 1
                }
            }
        }

        quotes = updated

        if successCount > 0 {
            if disconnectNotified && QuoteManager.disconnectAlertEnabled {
                NotificationManager.shared.send(
                    title: "StockWatch 재연결됨",
                    body: "시세 수신이 정상화됐습니다.",
                    symbol: "_system"
                )
            }
            consecutiveFailures = 0
            disconnectNotified = false
            connectionState = .connected
            AlertEvaluator.shared.evaluate(quotes: quotes)
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= 2 {
                connectionState = .error
                if !disconnectNotified && QuoteManager.disconnectAlertEnabled {
                    disconnectNotified = true
                    NotificationManager.shared.send(
                        title: "StockWatch 연결 끊김",
                        body: "시세 수신이 중단됐습니다. 네트워크를 확인해주세요.",
                        symbol: "_system"
                    )
                }
            }
        }
    }
}
