import Foundation

actor RealtimeQuoteManager {
    static let shared = RealtimeQuoteManager()
    private init() {}

    // MARK: - State

    private var webSocketTask: URLSessionWebSocketTask?
    private var credentials: BrokerCredentials?
    private var isMock = false
    private var approvalKey: String?
    private var subscribedSymbols: [String] = []
    private var isActive = false
    private var reconnectDelay: TimeInterval = 1.0
    private var connectionTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    private(set) var isConnected = false

    // QuoteManager가 주입하는 업데이트 콜백
    var onUpdate: (@Sendable (StockQuote) async -> Void)?

    // MARK: - Public Interface

    func setOnUpdate(_ closure: @escaping @Sendable (StockQuote) async -> Void) {
        onUpdate = closure
    }

    func start(credentials: BrokerCredentials, isMock: Bool, symbols: [String]) {
        self.credentials = credentials
        self.isMock = isMock
        self.subscribedSymbols = symbols
        self.isActive = true
        self.reconnectDelay = 1.0

        connectionTask?.cancel()
        connectionTask = Task { await self.runConnectionLoop() }
    }

    func stop() {
        isActive = false
        isConnected = false
        connectionTask?.cancel()
        pingTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    func updateSymbols(_ symbols: [String]) async {
        let current = Set(subscribedSymbols)
        let next = Set(symbols)

        for symbol in current.subtracting(next) {
            try? await sendSubscription(symbol: symbol, subscribe: false)
        }
        for symbol in next.subtracting(current) {
            try? await sendSubscription(symbol: symbol, subscribe: true)
        }
        subscribedSymbols = symbols
    }

    // MARK: - Connection Loop (Exponential Backoff)

    private func runConnectionLoop() async {
        while isActive && !Task.isCancelled {
            do {
                try await fetchApprovalKey()
                try connect()
                for symbol in subscribedSymbols {
                    try await sendSubscription(symbol: symbol, subscribe: true)
                }
                reconnectDelay = 1.0
                isConnected = true
                startPinging()
                await listen()       // 연결이 끊기면 여기서 반환
            } catch {
                APILogger.logError("[Realtime] 연결 실패: \(error.localizedDescription)", tag: "Realtime")
            }

            isConnected = false
            pingTask?.cancel()
            webSocketTask = nil

            guard isActive else { break }
            try? await Task.sleep(for: .seconds(reconnectDelay))
            reconnectDelay = min(reconnectDelay * 2, 60)
        }
    }

    // MARK: - WebSocket

    private func connect() throws {
        let urlString = isMock
            ? "ws://ops.koreainvestment.com:31000"
            : "ws://ops.koreainvestment.com:21000"
        guard let url = URL(string: urlString) else {
            throw BrokerError.apiError("잘못된 WebSocket URL")
        }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        webSocketTask = task
    }

    private func listen() async {
        while isActive, let task = webSocketTask {
            do {
                let message = try await task.receive()
                await handleMessage(message)
            } catch {
                break
            }
        }
    }

    private func startPinging() {
        pingTask?.cancel()
        pingTask = Task {
            while isActive, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                webSocketTask?.sendPing { _ in }
            }
        }
    }

    // MARK: - Subscription

    private func sendSubscription(symbol: String, subscribe: Bool) async throws {
        guard let key = approvalKey, let task = webSocketTask else {
            throw BrokerError.notConnected
        }

        let payload: [String: Any] = [
            "header": [
                "approval_key": key,
                "custtype": "P",
                "tr_type": subscribe ? "1" : "2",
                "content-type": "utf-8"
            ],
            "body": [
                "input": [
                    "tr_id": "H0STCNT0",
                    "tr_key": symbol
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BrokerError.apiError("직렬화 실패")
        }
        try await task.send(.string(text))
    }

    // MARK: - Approval Key

    private func fetchApprovalKey() async throws {
        guard let creds = credentials else { throw BrokerError.notConnected }

        let base = isMock
            ? "https://openapivts.koreainvestment.com:29443"
            : "https://openapi.koreainvestment.com:9443"

        var request = URLRequest(url: URL(string: "\(base)/oauth2/Approval")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "content-type")

        let body: [String: String] = [
            "grant_type": "client_credentials",
            "appkey": creds.appKey,
            "secretkey": creds.appSecret  // 승인키 발급은 secretkey 필드명 사용
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BrokerError.apiError("승인키 발급 실패")
        }

        struct ApprovalResponse: Decodable { let approval_key: String }
        let decoded = try JSONDecoder().decode(ApprovalResponse.self, from: data)
        approvalKey = decoded.approval_key
    }

    // MARK: - Message Parsing

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        guard case .string(let text) = message else { return }

        // 구독 확인 응답(JSON)은 무시
        guard !text.hasPrefix("{") else { return }

        // 형식: {encrypt}|{tr_id}|{count}|{data(^구분)}
        let parts = text.split(separator: "|", maxSplits: 3).map(String.init)
        guard parts.count == 4,
              parts[0] == "0",          // 0 = 미암호화
              parts[1] == "H0STCNT0"
        else { return }

        let fields = parts[3].split(separator: "^", omittingEmptySubsequences: false).map(String.init)
        guard fields.count > 13 else { return }

        let symbol    = fields[0]
        let price     = Int(fields[2]) ?? 0
        let sign      = fields[3]           // 2=상승 3=보합 4=하락 5=하한
        let absChange = Int(fields[4]) ?? 0
        let changeRate = Double(fields[5]) ?? 0
        let volume    = Int(fields[13]) ?? 0

        guard price > 0 else { return }

        let isNegative = sign == "4" || sign == "5"
        let changeAmount = isNegative ? -absChange : absChange

        let name = stockName(for: symbol)
        let quote = StockQuote(
            symbol: symbol,
            name: name,
            price: price,
            changeAmount: changeAmount,
            changeRate: changeRate,
            volume: volume,
            timestamp: Date()
        )

        await onUpdate?(quote)
    }

    private func stockName(for symbol: String) -> String {
        let items = try? DatabaseManager.shared.fetchWatchlist()
        return items?.first(where: { $0.symbol == symbol })?.name ?? symbol
    }
}
