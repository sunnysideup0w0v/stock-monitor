import Foundation

@MainActor
final class BrokerSessionManager: ObservableObject {
    static let shared = BrokerSessionManager()
    private init() {}

    // MARK: - Published State

    @Published private(set) var isKISConnected: Bool = false
    @Published private(set) var kisLoginDate: Date? = nil
    @Published private(set) var kisSavedAccountNumber: String = ""
    @Published private(set) var kisSavedIsMock: Bool = false

    @Published private(set) var isKiwoomConnected: Bool = false
    @Published private(set) var kiwoomLoginDate: Date? = nil
    @Published private(set) var kiwoomSavedAccountNumber: String = ""

    // MARK: - KIS

    func loginKIS(appKey: String, appSecret: String, accountNumber: String, isMock: Bool) {
        let accountId = "KIS-" + String(appKey.prefix(8))
        KeychainHelper.save(appKey, account: "kis.appKey")
        KeychainHelper.save(appSecret, account: "kis.appSecret")
        KeychainHelper.save(accountNumber, account: "kis.accountNumber")
        UserDefaults.standard.set(isMock, forKey: "KIS.isMock")
        let now = Date()
        UserDefaults.standard.set(now, forKey: "KIS.loginDate")
        try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)

        let creds = BrokerCredentials(
            appKey: appKey,
            appSecret: appSecret,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber
        )
        let adapter = KISAdapter(isMock: isMock)
        QuoteManager.shared.addAdapter(id: accountId, adapter: adapter)
        Task {
            try? await adapter.connect(credentials: creds)
            await MainActor.run { BrokerRegistry.shared.register(adapter) }
        }
        QuoteManager.shared.startRealtime(credentials: creds, isMock: isMock)

        isKISConnected = true
        kisLoginDate = now
        kisSavedAccountNumber = accountNumber
        kisSavedIsMock = isMock
    }

    func logoutKIS() {
        let accountId = "KIS-" + String((KeychainHelper.load(account: "kis.appKey") ?? "").prefix(8))
        KeychainHelper.delete(account: "kis.appKey")
        KeychainHelper.delete(account: "kis.appSecret")
        KeychainHelper.delete(account: "kis.accountNumber")
        UserDefaults.standard.removeObject(forKey: "KIS.loginDate")
        QuoteManager.shared.stopRealtime()
        QuoteManager.shared.removeAdapter(id: accountId)
        BrokerRegistry.shared.unregister(brokerName: "한국투자증권")

        isKISConnected = false
        kisLoginDate = nil
    }

    func testConnectionKIS(appKey: String, appSecret: String, accountNumber: String, isMock: Bool) async throws {
        let creds = BrokerCredentials(
            appKey: appKey,
            appSecret: appSecret,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber
        )
        let adapter = KISAdapter(isMock: isMock)
        try await adapter.connect(credentials: creds)
        _ = try await adapter.fetchQuote(symbol: "005930")
    }

    // MARK: - Kiwoom

    func loginKiwoom(appKey: String, appSecret: String, accountNumber: String) {
        let accountId = "KIWOOM-" + String(appKey.prefix(8))
        KeychainHelper.save(appKey, account: "kiwoom.appKey")
        KeychainHelper.save(appSecret, account: "kiwoom.appSecret")
        KeychainHelper.save(accountNumber, account: "kiwoom.accountNumber")
        let now = Date()
        UserDefaults.standard.set(now, forKey: "Kiwoom.loginDate")
        try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)

        let creds = BrokerCredentials(
            appKey: appKey,
            appSecret: appSecret,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber
        )
        let adapter = KiwoomAdapter()
        QuoteManager.shared.addAdapter(id: accountId, adapter: adapter)
        Task {
            try? await adapter.connect(credentials: creds)
            await MainActor.run { BrokerRegistry.shared.register(adapter) }
        }

        isKiwoomConnected = true
        kiwoomLoginDate = now
        kiwoomSavedAccountNumber = accountNumber
    }

    func logoutKiwoom() {
        let accountId = "KIWOOM-" + String((KeychainHelper.load(account: "kiwoom.appKey") ?? "").prefix(8))
        KeychainHelper.delete(account: "kiwoom.appKey")
        KeychainHelper.delete(account: "kiwoom.appSecret")
        KeychainHelper.delete(account: "kiwoom.accountNumber")
        UserDefaults.standard.removeObject(forKey: "Kiwoom.loginDate")
        QuoteManager.shared.removeAdapter(id: accountId)
        BrokerRegistry.shared.unregister(brokerName: "키움증권")

        isKiwoomConnected = false
        kiwoomLoginDate = nil
    }

    func testConnectionKiwoom(appKey: String, appSecret: String, accountNumber: String) async throws {
        let creds = BrokerCredentials(
            appKey: appKey,
            appSecret: appSecret,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber
        )
        let adapter = KiwoomAdapter()
        try await adapter.connect(credentials: creds)
        _ = try await adapter.fetchQuote(symbol: "005930")
    }

    // MARK: - 앱 시작 시 세션 복원

    func restoreAllSessions() {
        var hasRealAdapter = false

        if let appKey = KeychainHelper.load(account: "kis.appKey"),
           let appSecret = KeychainHelper.load(account: "kis.appSecret"),
           !appKey.isEmpty, !appSecret.isEmpty {
            let isMock = UserDefaults.standard.bool(forKey: "KIS.isMock")
            let accountNumber = KeychainHelper.load(account: "kis.accountNumber")
            let creds = BrokerCredentials(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber)
            let adapter = KISAdapter(isMock: isMock)
            let accountId = "KIS-" + String(appKey.prefix(8))
            QuoteManager.shared.addAdapter(id: accountId, adapter: adapter)
            try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)
            Task {
                try? await adapter.connect(credentials: creds)
                await MainActor.run { BrokerRegistry.shared.register(adapter) }
            }
            QuoteManager.shared.startRealtime(credentials: creds, isMock: isMock)
            hasRealAdapter = true
        }

        if let appKey = KeychainHelper.load(account: "kiwoom.appKey"),
           let appSecret = KeychainHelper.load(account: "kiwoom.appSecret"),
           !appKey.isEmpty, !appSecret.isEmpty {
            let accountNumber = KeychainHelper.load(account: "kiwoom.accountNumber")
            let creds = BrokerCredentials(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber)
            let adapter = KiwoomAdapter()
            let accountId = "KIWOOM-" + String(appKey.prefix(8))
            QuoteManager.shared.addAdapter(id: accountId, adapter: adapter)
            try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)
            Task {
                try? await adapter.connect(credentials: creds)
                await MainActor.run { BrokerRegistry.shared.register(adapter) }
            }
            hasRealAdapter = true
        }

        if !hasRealAdapter {
            QuoteManager.shared.setAdapter(MockBrokerAdapter())
        }

        loadState()
    }

    // MARK: - UI 상태 동기화

    func loadState() {
        isKISConnected = !(KeychainHelper.load(account: "kis.appKey") ?? "").isEmpty
        kisSavedAccountNumber = KeychainHelper.load(account: "kis.accountNumber") ?? ""
        kisSavedIsMock = UserDefaults.standard.bool(forKey: "KIS.isMock")
        kisLoginDate = UserDefaults.standard.object(forKey: "KIS.loginDate") as? Date

        isKiwoomConnected = !(KeychainHelper.load(account: "kiwoom.appKey") ?? "").isEmpty
        kiwoomSavedAccountNumber = KeychainHelper.load(account: "kiwoom.accountNumber") ?? ""
        kiwoomLoginDate = UserDefaults.standard.object(forKey: "Kiwoom.loginDate") as? Date
    }
}
