import SwiftUI
import ServiceManagement

struct AccountSettingsView: View {
    @State private var selectedBroker: BrokerSelection = .kis

    // KIS 상태
    @State private var appKey = ""
    @State private var appSecret = ""
    @State private var accountNumber = ""
    @State private var isMock = false
    @State private var isLoggedIn = false
    @State private var loginDate: Date? = nil
    @State private var savedAccountNumber = ""
    @State private var savedIsMock = false

    // 키움 상태
    @State private var kiwoomAppKey = ""
    @State private var kiwoomAppSecret = ""
    @State private var kiwoomAccountNumber = ""
    @State private var isKiwoomLoggedIn = false
    @State private var kiwoomLoginDate: Date? = nil
    @State private var savedKiwoomAccountNumber = ""

    @State private var testStatus: TestStatus = .idle
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    enum BrokerSelection: String, CaseIterable {
        case kis        = "한국투자증권"
        case kiwoom     = "키움증권"
        case miraeAsset = "미래에셋증권"
    }

    enum TestStatus: Equatable {
        case idle, testing, success, failure(String)
        var label: String {
            switch self {
            case .idle:            return ""
            case .testing:         return "연결 확인 중…"
            case .success:         return "연결 성공"
            case .failure(let m):  return m
            }
        }
        var color: Color {
            switch self {
            case .idle:    return .clear
            case .testing: return .orange
            case .success: return .green
            case .failure: return .red
            }
        }
    }

    var body: some View {
        SettingsTabContainer(title: "계좌 연결") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    brokerPickerSection
                    Divider()
                    switch selectedBroker {
                    case .kis:
                        if isLoggedIn { loggedInView } else { loginFormView }
                    case .kiwoom:
                        if isKiwoomLoggedIn { kiwoomLoggedInView } else { kiwoomLoginFormView }
                    case .miraeAsset:
                        comingSoonView
                    }
                    launchAtLoginSection
                    DARTSettingsView()
                    KRXSettingsView()
                    ClaudeSettingsView()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 8)
                .dismissFocusOnTap()
            }
        }
        .onAppear { loadState() }
    }

    // MARK: - 브로커 선택

    private var brokerPickerSection: some View {
        HStack(spacing: 12) {
            Text("브로커")
                .foregroundStyle(.secondary)
            Picker("", selection: $selectedBroker) {
                ForEach(BrokerSelection.allCases, id: \.self) { broker in
                    let connected: Bool = {
                        switch broker {
                        case .kis:        return isLoggedIn
                        case .kiwoom:     return isKiwoomLoggedIn
                        case .miraeAsset: return false
                        }
                    }()
                    Text(broker.rawValue + (connected ? " ✓" : "")).tag(broker)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            Spacer()
        }
    }

    // MARK: - 키움증권 로그인 뷰

    private var kiwoomLoggedInView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 10, height: 10)
                Text("연결됨").font(.headline).foregroundStyle(.green)
                Text("·")
                Text("키움증권").font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("계좌번호").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(savedKiwoomAccountNumber.isEmpty ? "미입력" : savedKiwoomAccountNumber)
                        .fontDesign(.monospaced)
                }
                GridRow {
                    Text("앱 키").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(maskedKey(KeychainHelper.load(account: "kiwoom.appKey") ?? ""))
                        .fontDesign(.monospaced).foregroundStyle(.secondary)
                }
                if let date = kiwoomLoginDate {
                    GridRow {
                        Text("로그인 시각").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(date, style: .date) + Text(" ") + Text(date, style: .time)
                    }
                }
            }
            .font(.body)
            Divider()
            HStack {
                Button("로그아웃", role: .destructive) { kiwoomLogout() }
                Spacer()
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var kiwoomLoginFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("키움증권 Open API에서 발급한 App Key와 App Secret을 입력하세요.")
                .font(.caption).foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 12) {
                GridRow {
                    Text("App Key").gridColumnAlignment(.trailing)
                    SecureField("앱 키", text: $kiwoomAppKey).gridCellColumns(3)
                }
                GridRow {
                    Text("App Secret").gridColumnAlignment(.trailing)
                    SecureField("앱 시크릿", text: $kiwoomAppSecret).gridCellColumns(3)
                }
                GridRow {
                    Text("계좌번호").gridColumnAlignment(.trailing)
                    TextField("예: 1234567890", text: $kiwoomAccountNumber).gridCellColumns(3)
                }
            }

            HStack(spacing: 12) {
                Button("로그인") { kiwoomLogin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(kiwoomAppKey.isEmpty || kiwoomAppSecret.isEmpty)
                Button("연결 테스트") { kiwoomTestConnection() }
                    .disabled(kiwoomAppKey.isEmpty || kiwoomAppSecret.isEmpty)
                if testStatus != .idle {
                    Circle().fill(testStatus.color).frame(width: 7, height: 7)
                    Text(testStatus.label).font(.caption).foregroundStyle(testStatus.color)
                }
            }
        }
    }

    // MARK: - 준비 중 (미래에셋 등)

    private var comingSoonView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge").foregroundStyle(.secondary)
                Text("준비 중").font(.headline).foregroundStyle(.secondary)
            }
            Text("\(selectedBroker.rawValue) Open API 연동은 다음 업데이트에서 추가될 예정입니다.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var launchAtLoginSection: some View {
        SettingsFormSection(title: "앱 설정") {
            HStack {
                Toggle("로그인 시 자동 시작", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }
                Spacer()
            }
            HStack(spacing: 12) {
                Button("설정 백업…") { BackupManager.export() }
                Button("설정 복원…") { BackupManager.importBackup() }
                Spacer()
            }
        }
    }

    // MARK: - 로그인 상태 뷰

    private var loggedInView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 10, height: 10)
                Text("연결됨").font(.headline).foregroundStyle(.green)
                Text("·")
                Text(savedIsMock ? "모의투자" : "실전투자")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("계좌번호").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(savedAccountNumber.isEmpty ? "미입력" : savedAccountNumber)
                        .fontDesign(.monospaced)
                }
                GridRow {
                    Text("앱 키").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(maskedKey(KeychainHelper.load(account: "kis.appKey") ?? ""))
                        .fontDesign(.monospaced).foregroundStyle(.secondary)
                }
                if let date = loginDate {
                    GridRow {
                        Text("로그인 시각").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(date, style: .date) + Text(" ") + Text(date, style: .time)
                    }
                }
            }
            .font(.body)

            Divider()

            HStack {
                Button("로그아웃", role: .destructive) { logout() }
                Spacer()
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 로그인 폼 뷰

    private var loginFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("한국투자증권 KIS Developers에서 발급한 API 키를 입력하세요.")
                .font(.caption).foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 12) {
                GridRow {
                    Text("App Key").gridColumnAlignment(.trailing)
                    SecureField("앱 키", text: $appKey).gridCellColumns(3)
                }
                GridRow {
                    Text("App Secret").gridColumnAlignment(.trailing)
                    SecureField("앱 시크릿", text: $appSecret).gridCellColumns(3)
                }
                GridRow {
                    Text("계좌번호").gridColumnAlignment(.trailing)
                    TextField("예: 50123456-01", text: $accountNumber).gridCellColumns(3)
                }
                GridRow {
                    Text("").gridColumnAlignment(.trailing)
                    Toggle("모의투자 계정", isOn: $isMock).gridCellColumns(3)
                }
            }

            HStack(spacing: 12) {
                Button("로그인") { login() }
                    .buttonStyle(.borderedProminent)
                    .disabled(appKey.isEmpty || appSecret.isEmpty)
                Button("연결 테스트") { testConnection() }
                    .disabled(appKey.isEmpty || appSecret.isEmpty)
                if testStatus != .idle {
                    Circle().fill(testStatus.color).frame(width: 7, height: 7)
                    Text(testStatus.label)
                        .font(.caption).foregroundStyle(testStatus.color)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadState() {
        isLoggedIn = !(KeychainHelper.load(account: "kis.appKey") ?? "").isEmpty
        savedAccountNumber = KeychainHelper.load(account: "kis.accountNumber") ?? ""
        savedIsMock = UserDefaults.standard.bool(forKey: "KIS.isMock")
        loginDate = UserDefaults.standard.object(forKey: "KIS.loginDate") as? Date

        isKiwoomLoggedIn = !(KeychainHelper.load(account: "kiwoom.appKey") ?? "").isEmpty
        savedKiwoomAccountNumber = KeychainHelper.load(account: "kiwoom.accountNumber") ?? ""
        kiwoomLoginDate = UserDefaults.standard.object(forKey: "Kiwoom.loginDate") as? Date

        if !isLoggedIn && isKiwoomLoggedIn { selectedBroker = .kiwoom }
        else { selectedBroker = .kis }
    }

    private func login() {
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

        withAnimation {
            savedAccountNumber = accountNumber
            savedIsMock = isMock
            loginDate = now
            isLoggedIn = true
            appKey = ""; appSecret = ""; accountNumber = ""
        }
    }

    private func logout() {
        let accountId = "KIS-" + String((KeychainHelper.load(account: "kis.appKey") ?? "").prefix(8))
        KeychainHelper.delete(account: "kis.appKey")
        KeychainHelper.delete(account: "kis.appSecret")
        KeychainHelper.delete(account: "kis.accountNumber")
        UserDefaults.standard.removeObject(forKey: "KIS.loginDate")
        QuoteManager.shared.stopRealtime()
        QuoteManager.shared.removeAdapter(id: accountId)
        BrokerRegistry.shared.unregister(brokerName: "한국투자증권")
        withAnimation { isLoggedIn = false; loginDate = nil; testStatus = .idle }
    }

    // MARK: - 키움 Actions

    private func kiwoomLogin() {
        let accountId = "KIWOOM-" + String(kiwoomAppKey.prefix(8))
        KeychainHelper.save(kiwoomAppKey, account: "kiwoom.appKey")
        KeychainHelper.save(kiwoomAppSecret, account: "kiwoom.appSecret")
        KeychainHelper.save(kiwoomAccountNumber, account: "kiwoom.accountNumber")
        let now = Date()
        UserDefaults.standard.set(now, forKey: "Kiwoom.loginDate")
        try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)

        let creds = BrokerCredentials(
            appKey: kiwoomAppKey,
            appSecret: kiwoomAppSecret,
            accountNumber: kiwoomAccountNumber.isEmpty ? nil : kiwoomAccountNumber
        )
        let adapter = KiwoomAdapter()
        QuoteManager.shared.addAdapter(id: accountId, adapter: adapter)
        Task {
            try? await adapter.connect(credentials: creds)
            await MainActor.run { BrokerRegistry.shared.register(adapter) }
        }

        withAnimation {
            savedKiwoomAccountNumber = kiwoomAccountNumber
            kiwoomLoginDate = now
            isKiwoomLoggedIn = true
            kiwoomAppKey = ""; kiwoomAppSecret = ""; kiwoomAccountNumber = ""
            testStatus = .idle
        }
    }

    private func kiwoomLogout() {
        let accountId = "KIWOOM-" + String((KeychainHelper.load(account: "kiwoom.appKey") ?? "").prefix(8))
        KeychainHelper.delete(account: "kiwoom.appKey")
        KeychainHelper.delete(account: "kiwoom.appSecret")
        KeychainHelper.delete(account: "kiwoom.accountNumber")
        UserDefaults.standard.removeObject(forKey: "Kiwoom.loginDate")
        QuoteManager.shared.removeAdapter(id: accountId)
        BrokerRegistry.shared.unregister(brokerName: "키움증권")
        withAnimation { isKiwoomLoggedIn = false; kiwoomLoginDate = nil; testStatus = .idle }
    }

    private func kiwoomTestConnection() {
        testStatus = .testing
        let creds = BrokerCredentials(
            appKey: kiwoomAppKey,
            appSecret: kiwoomAppSecret,
            accountNumber: kiwoomAccountNumber.isEmpty ? nil : kiwoomAccountNumber
        )
        let adapter = KiwoomAdapter()
        Task {
            do {
                try await adapter.connect(credentials: creds)
                _ = try await adapter.fetchQuote(symbol: "005930")
                testStatus = .success
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func testConnection() {
        testStatus = .testing
        let creds = BrokerCredentials(
            appKey: appKey,
            appSecret: appSecret,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber
        )
        let adapter = KISAdapter(isMock: isMock)
        Task {
            do {
                try await adapter.connect(credentials: creds)
                _ = try await adapter.fetchQuote(symbol: "005930")
                testStatus = .success
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        return String(key.prefix(4)) + String(repeating: "•", count: 12) + String(key.suffix(4))
    }
}
