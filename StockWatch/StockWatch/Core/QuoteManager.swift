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

    private var adapter: (any BrokerAdapter)?
    private var pollingTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private(set) var currentSymbols: [String] = []

    private init() {}

    func setAdapter(_ adapter: any BrokerAdapter) {
        self.adapter = adapter
        consecutiveFailures = 0
        connectionState = .disconnected
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

    func fetchBalance() async throws -> [PortfolioItem] {
        guard let adapter else { throw BrokerError.notConnected }
        return try await adapter.fetchPortfolio()
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func fetchAll(symbols: [String]) async {
        guard let adapter else { return }
        var updated = quotes
        var successCount = 0

        await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in symbols {
                group.addTask {
                    let quote = try? await adapter.fetchQuote(symbol: symbol)
                    return (symbol, quote)
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
            consecutiveFailures = 0
            connectionState = .connected
            AlertEvaluator.shared.evaluate(quotes: quotes)
        } else {
            consecutiveFailures += 1
            // 2회 연속 실패 시 오류 상태로 전환
            if consecutiveFailures >= 2 {
                connectionState = .error
            }
        }
    }
}
