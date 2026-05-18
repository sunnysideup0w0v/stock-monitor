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
        KeychainHelper.save(appKey, account: KeychainKey.kisAppKey)
        KeychainHelper.save(appSecret, account: KeychainKey.kisAppSecret)
        KeychainHelper.save(accountNumber, account: KeychainKey.kisAccountNumber)
        UserDefaults.standard.set(isMock, forKey: UserDefaultsKey.kisMock)
        let now = Date()
        UserDefaults.standard.set(now, forKey: UserDefaultsKey.kisLoginDate)
        try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)

        let creds = BrokerCredentials(
            appKey: appKey,
            appSecret: appSecret,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber
        )
        let adapter = KISAdapter(isMock: isMock)
        addBroker(id: accountId, adapter: adapter, credentials: creds)
        QuoteManager.shared.startRealtime(credentials: creds, isMock: isMock)

        AccountManager.invalidateCache()
        isKISConnected = true
        kisLoginDate = now
        kisSavedAccountNumber = accountNumber
        kisSavedIsMock = isMock
    }

    func logoutKIS() {
        let accountId = "KIS-" + String((KeychainHelper.load(account: KeychainKey.kisAppKey) ?? "").prefix(8))
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
        KeychainHelper.delete(account: KeychainKey.kisAppSecret)
        KeychainHelper.delete(account: KeychainKey.kisAccountNumber)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.kisLoginDate)
        QuoteManager.shared.stopRealtime()
        removeBroker(id: accountId, brokerName: "한국투자증권")

        AccountManager.invalidateCache()
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
        KeychainHelper.save(appKey, account: KeychainKey.kiwoomAppKey)
        KeychainHelper.save(appSecret, account: KeychainKey.kiwoomAppSecret)
        KeychainHelper.save(accountNumber, account: KeychainKey.kiwoomAccountNumber)
        let now = Date()
        UserDefaults.standard.set(now, forKey: UserDefaultsKey.kiwoomLoginDate)
        try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)

        let creds = BrokerCredentials(
            appKey: appKey,
            appSecret: appSecret,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber
        )
        let adapter = KiwoomAdapter()
        addBroker(id: accountId, adapter: adapter, credentials: creds)

        AccountManager.invalidateCache()
        isKiwoomConnected = true
        kiwoomLoginDate = now
        kiwoomSavedAccountNumber = accountNumber
    }

    func logoutKiwoom() {
        let accountId = "KIWOOM-" + String((KeychainHelper.load(account: KeychainKey.kiwoomAppKey) ?? "").prefix(8))
        KeychainHelper.delete(account: KeychainKey.kiwoomAppKey)
        KeychainHelper.delete(account: KeychainKey.kiwoomAppSecret)
        KeychainHelper.delete(account: KeychainKey.kiwoomAccountNumber)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.kiwoomLoginDate)
        removeBroker(id: accountId, brokerName: "키움증권")

        AccountManager.invalidateCache()
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

        if let appKey = KeychainHelper.load(account: KeychainKey.kisAppKey),
           let appSecret = KeychainHelper.load(account: KeychainKey.kisAppSecret),
           !appKey.isEmpty, !appSecret.isEmpty {
            let isMock = UserDefaults.standard.bool(forKey: UserDefaultsKey.kisMock)
            let accountNumber = KeychainHelper.load(account: KeychainKey.kisAccountNumber)
            let creds = BrokerCredentials(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber)
            let adapter = KISAdapter(isMock: isMock)
            let accountId = "KIS-" + String(appKey.prefix(8))
            try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)
            addBroker(id: accountId, adapter: adapter, credentials: creds)
            QuoteManager.shared.startRealtime(credentials: creds, isMock: isMock)
            hasRealAdapter = true
        }

        if let appKey = KeychainHelper.load(account: KeychainKey.kiwoomAppKey),
           let appSecret = KeychainHelper.load(account: KeychainKey.kiwoomAppSecret),
           !appKey.isEmpty, !appSecret.isEmpty {
            let accountNumber = KeychainHelper.load(account: KeychainKey.kiwoomAccountNumber)
            let creds = BrokerCredentials(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber)
            let adapter = KiwoomAdapter()
            let accountId = "KIWOOM-" + String(appKey.prefix(8))
            try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)
            addBroker(id: accountId, adapter: adapter, credentials: creds)
            hasRealAdapter = true
        }

        if !hasRealAdapter {
            QuoteManager.shared.setAdapter(MockBrokerAdapter())
        }

        loadState()
    }

    // MARK: - 어댑터 등록/해제 래퍼 (QuoteManager + BrokerRegistry 항상 함께 처리)

    private func addBroker(id: String, adapter: some BrokerAdapter, credentials: BrokerCredentials) {
        QuoteManager.shared.addAdapter(id: id, adapter: adapter)
        Task {
            try? await adapter.connect(credentials: credentials)
            await MainActor.run { BrokerRegistry.shared.register(adapter) }
        }
    }

    private func removeBroker(id: String, brokerName: String) {
        QuoteManager.shared.removeAdapter(id: id)
        BrokerRegistry.shared.unregister(brokerName: brokerName)
    }

    // MARK: - UI 상태 동기화

    func loadState() {
        isKISConnected = !(KeychainHelper.load(account: KeychainKey.kisAppKey) ?? "").isEmpty
        kisSavedAccountNumber = KeychainHelper.load(account: KeychainKey.kisAccountNumber) ?? ""
        kisSavedIsMock = UserDefaults.standard.bool(forKey: UserDefaultsKey.kisMock)
        kisLoginDate = UserDefaults.standard.object(forKey: UserDefaultsKey.kisLoginDate) as? Date

        isKiwoomConnected = !(KeychainHelper.load(account: KeychainKey.kiwoomAppKey) ?? "").isEmpty
        kiwoomSavedAccountNumber = KeychainHelper.load(account: KeychainKey.kiwoomAccountNumber) ?? ""
        kiwoomLoginDate = UserDefaults.standard.object(forKey: UserDefaultsKey.kiwoomLoginDate) as? Date
    }
}
