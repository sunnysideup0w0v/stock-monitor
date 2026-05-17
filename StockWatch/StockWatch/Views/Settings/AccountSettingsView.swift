import SwiftUI
import ServiceManagement

struct AccountSettingsView: View {
    @ObservedObject private var session = BrokerSessionManager.shared

    @State private var selectedBroker: BrokerSelection = .kis

    // KIS 입력 폼
    @State private var appKey = ""
    @State private var appSecret = ""
    @State private var accountNumber = ""
    @State private var isMock = false

    // 키움 입력 폼
    @State private var kiwoomAppKey = ""
    @State private var kiwoomAppSecret = ""
    @State private var kiwoomAccountNumber = ""

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
                        if session.isKISConnected { loggedInView } else { loginFormView }
                    case .kiwoom:
                        if session.isKiwoomConnected { kiwoomLoggedInView } else { kiwoomLoginFormView }
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
        .onAppear { loadInitialBrokerTab() }
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
                        case .kis:        return session.isKISConnected
                        case .kiwoom:     return session.isKiwoomConnected
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
                    Text(session.kiwoomSavedAccountNumber.isEmpty ? "미입력" : session.kiwoomSavedAccountNumber)
                        .fontDesign(.monospaced)
                }
                GridRow {
                    Text("앱 키").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(maskedKey(KeychainHelper.load(account: KeychainKey.kiwoomAppKey) ?? ""))
                        .fontDesign(.monospaced).foregroundStyle(.secondary)
                }
                if let date = session.kiwoomLoginDate {
                    GridRow {
                        Text("로그인 시각").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(date, style: .date) + Text(" ") + Text(date, style: .time)
                    }
                }
            }
            .font(.body)
            Divider()
            HStack {
                Button("로그아웃", role: .destructive) {
                    withAnimation { session.logoutKiwoom() }
                    testStatus = .idle
                }
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
                Text(session.kisSavedIsMock ? "모의투자" : "실전투자")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("계좌번호").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(session.kisSavedAccountNumber.isEmpty ? "미입력" : session.kisSavedAccountNumber)
                        .fontDesign(.monospaced)
                }
                GridRow {
                    Text("앱 키").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(maskedKey(KeychainHelper.load(account: KeychainKey.kisAppKey) ?? ""))
                        .fontDesign(.monospaced).foregroundStyle(.secondary)
                }
                if let date = session.kisLoginDate {
                    GridRow {
                        Text("로그인 시각").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(date, style: .date) + Text(" ") + Text(date, style: .time)
                    }
                }
            }
            .font(.body)

            Divider()

            HStack {
                Button("로그아웃", role: .destructive) {
                    withAnimation { session.logoutKIS() }
                    testStatus = .idle
                }
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

    private func loadInitialBrokerTab() {
        session.loadState()
        if !session.isKISConnected && session.isKiwoomConnected { selectedBroker = .kiwoom }
        else { selectedBroker = .kis }
    }

    private func login() {
        session.loginKIS(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber, isMock: isMock)
        withAnimation { appKey = ""; appSecret = ""; accountNumber = "" }
    }

    private func kiwoomLogin() {
        session.loginKiwoom(appKey: kiwoomAppKey, appSecret: kiwoomAppSecret, accountNumber: kiwoomAccountNumber)
        withAnimation {
            kiwoomAppKey = ""; kiwoomAppSecret = ""; kiwoomAccountNumber = ""
            testStatus = .idle
        }
    }

    private func testConnection() {
        testStatus = .testing
        let key = appKey, secret = appSecret, acct = accountNumber, mock = isMock
        Task {
            do {
                try await session.testConnectionKIS(appKey: key, appSecret: secret, accountNumber: acct, isMock: mock)
                testStatus = .success
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func kiwoomTestConnection() {
        testStatus = .testing
        let key = kiwoomAppKey, secret = kiwoomAppSecret, acct = kiwoomAccountNumber
        Task {
            do {
                try await session.testConnectionKiwoom(appKey: key, appSecret: secret, accountNumber: acct)
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
