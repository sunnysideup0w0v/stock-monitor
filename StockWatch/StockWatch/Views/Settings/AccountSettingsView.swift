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

    // 생체 인증 자동 입력
    @State private var hasBiometricKIS = false
    @State private var hasBiometricKiwoom = false
    @State private var isAutoFilling = false
    @State private var autoFillError: String? = nil
    @State private var biometricJustSaved: String? = nil  // "kis" | "kiwoom"

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
        .onChange(of: selectedBroker) { _, _ in autoFillError = nil }
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

    // MARK: - KIS 로그인 상태 뷰

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
                    Text(KeychainHelper.masked(KeychainHelper.load(account: KeychainKey.kisAppKey) ?? ""))
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

            if BiometricAuthManager.isAvailable {
                Divider()
                biometricStatusRow(
                    hasCredentials: hasBiometricKIS,
                    justSaved: biometricJustSaved == "kis",
                    onSave: { saveKISBiometric() },
                    onDelete: {
                        BiometricAuthManager.deleteCredentials(keyPrefix: "kis")
                        withAnimation { hasBiometricKIS = false }
                    }
                )
            }

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

    // MARK: - KIS 로그인 폼 뷰

    private var loginFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if BiometricAuthManager.isAvailable && hasBiometricKIS {
                autoFillButton(keyPrefix: "kis", reason: "KIS API 키에 접근합니다") {
                    BiometricAuthManager.deleteCredentials(keyPrefix: "kis")
                    hasBiometricKIS = false
                } onFill: { creds in
                    appKey = creds.appKey
                    appSecret = creds.appSecret
                    accountNumber = creds.accountNumber
                }
                dividerWithLabel("또는")
            }

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

            if BiometricAuthManager.isAvailable && !hasBiometricKIS {
                Text("로그인 후 Touch ID 보호 키체인에 자동 저장됩니다")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 키움증권 로그인 상태 뷰

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
                    Text(KeychainHelper.masked(KeychainHelper.load(account: KeychainKey.kiwoomAppKey) ?? ""))
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

            if BiometricAuthManager.isAvailable {
                Divider()
                biometricStatusRow(
                    hasCredentials: hasBiometricKiwoom,
                    justSaved: biometricJustSaved == "kiwoom",
                    onSave: { saveKiwoomBiometric() },
                    onDelete: {
                        BiometricAuthManager.deleteCredentials(keyPrefix: "kiwoom")
                        withAnimation { hasBiometricKiwoom = false }
                    }
                )
            }

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

    // MARK: - 키움증권 로그인 폼 뷰

    private var kiwoomLoginFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if BiometricAuthManager.isAvailable && hasBiometricKiwoom {
                autoFillButton(keyPrefix: "kiwoom", reason: "키움증권 API 키에 접근합니다") {
                    BiometricAuthManager.deleteCredentials(keyPrefix: "kiwoom")
                    hasBiometricKiwoom = false
                } onFill: { creds in
                    kiwoomAppKey = creds.appKey
                    kiwoomAppSecret = creds.appSecret
                    kiwoomAccountNumber = creds.accountNumber
                }
                dividerWithLabel("또는")
            }

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

            if BiometricAuthManager.isAvailable && !hasBiometricKiwoom {
                Text("로그인 후 Touch ID 보호 키체인에 자동 저장됩니다")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 공용 컴포넌트

    /// 로그인 상태 화면에서 Touch ID 저장 여부와 저장/삭제 버튼
    @ViewBuilder
    private func biometricStatusRow(
        hasCredentials: Bool,
        justSaved: Bool,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            if hasCredentials {
                if justSaved {
                    Label("저장됐습니다", systemImage: "checkmark.shield.fill")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.green)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    Label("\(BiometricAuthManager.methodName) 보호 저장됨", systemImage: "checkmark.shield.fill")
                        .font(.caption).foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()
                Button("삭제", role: .destructive) { onDelete() }
                    .font(.caption)
            } else {
                Label("\(BiometricAuthManager.methodName) 저장 없음", systemImage: "shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("\(BiometricAuthManager.methodName)로 저장") { onSave() }
                    .font(.caption)
            }
        }
    }

    /// 로그인 폼 최상단 자동 입력 버튼 블록
    @ViewBuilder
    private func autoFillButton(
        keyPrefix: String,
        reason: String,
        onDelete: @escaping () -> Void,
        onFill: @escaping (BiometricAuthManager.Credentials) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    Task { await performAutoFill(keyPrefix: keyPrefix, reason: reason, onFill: onFill) }
                } label: {
                    if isAutoFilling {
                        ProgressView().scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("\(BiometricAuthManager.methodName)로 자동 입력",
                              systemImage: BiometricAuthManager.methodIcon)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAutoFilling)

                Spacer()

                Button("저장 삭제", role: .destructive) { onDelete() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = autoFillError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func dividerWithLabel(_ label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text(label).font(.caption).foregroundStyle(.tertiary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 준비 중

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

    // MARK: - 앱 설정 섹션

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

    // MARK: - Actions

    private func loadInitialBrokerTab() {
        session.loadState()
        if !session.isKISConnected && session.isKiwoomConnected { selectedBroker = .kiwoom }
        else { selectedBroker = .kis }
        hasBiometricKIS    = BiometricAuthManager.hasStoredCredentials(keyPrefix: "kis")
        hasBiometricKiwoom = BiometricAuthManager.hasStoredCredentials(keyPrefix: "kiwoom")
    }

    private func login() {
        let creds = BiometricAuthManager.Credentials(
            appKey: appKey, appSecret: appSecret, accountNumber: accountNumber
        )
        session.loginKIS(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber, isMock: isMock)
        BiometricAuthManager.saveCredentials(creds, keyPrefix: "kis")
        hasBiometricKIS = BiometricAuthManager.hasStoredCredentials(keyPrefix: "kis")
        withAnimation { appKey = ""; appSecret = ""; accountNumber = "" }
    }

    private func kiwoomLogin() {
        let creds = BiometricAuthManager.Credentials(
            appKey: kiwoomAppKey, appSecret: kiwoomAppSecret, accountNumber: kiwoomAccountNumber
        )
        session.loginKiwoom(appKey: kiwoomAppKey, appSecret: kiwoomAppSecret, accountNumber: kiwoomAccountNumber)
        BiometricAuthManager.saveCredentials(creds, keyPrefix: "kiwoom")
        hasBiometricKiwoom = BiometricAuthManager.hasStoredCredentials(keyPrefix: "kiwoom")
        withAnimation {
            kiwoomAppKey = ""; kiwoomAppSecret = ""; kiwoomAccountNumber = ""
            testStatus = .idle
        }
    }

    private func saveKISBiometric() {
        guard let key    = KeychainHelper.load(account: KeychainKey.kisAppKey),
              let secret = KeychainHelper.load(account: KeychainKey.kisAppSecret) else {
            autoFillError = "저장된 자격증명을 불러올 수 없습니다"
            return
        }
        let creds = BiometricAuthManager.Credentials(
            appKey: key, appSecret: secret, accountNumber: session.kisSavedAccountNumber
        )
        let success = BiometricAuthManager.saveCredentials(creds, keyPrefix: "kis")
        if success {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                hasBiometricKIS = true
                biometricJustSaved = "kis"
            }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.4)) { biometricJustSaved = nil }
            }
        } else {
            autoFillError = "Touch ID 저장에 실패했습니다 (Console.app에서 StockWatch 로그 확인)"
        }
    }

    private func saveKiwoomBiometric() {
        guard let key    = KeychainHelper.load(account: KeychainKey.kiwoomAppKey),
              let secret = KeychainHelper.load(account: KeychainKey.kiwoomAppSecret) else {
            autoFillError = "저장된 자격증명을 불러올 수 없습니다"
            return
        }
        let creds = BiometricAuthManager.Credentials(
            appKey: key, appSecret: secret, accountNumber: session.kiwoomSavedAccountNumber
        )
        let success = BiometricAuthManager.saveCredentials(creds, keyPrefix: "kiwoom")
        if success {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                hasBiometricKiwoom = true
                biometricJustSaved = "kiwoom"
            }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.4)) { biometricJustSaved = nil }
            }
        } else {
            autoFillError = "Touch ID 저장에 실패했습니다 (Console.app에서 StockWatch 로그 확인)"
        }
    }

    private func performAutoFill(
        keyPrefix: String,
        reason: String,
        onFill: @escaping (BiometricAuthManager.Credentials) -> Void
    ) async {
        isAutoFilling = true
        autoFillError = nil
        do {
            let creds = try await BiometricAuthManager.loadCredentials(keyPrefix: keyPrefix, reason: reason)
            onFill(creds)
        } catch BiometricAuthManager.CredentialError.authCancelled {
            // 사용자 취소: 메시지 불필요
        } catch {
            autoFillError = error.localizedDescription
        }
        isAutoFilling = false
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
}
