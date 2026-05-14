import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem { Label("계좌 연결", systemImage: "key.fill") }
            WatchlistSettingsView()
                .tabItem { Label("관심종목", systemImage: "list.star") }
            PortfolioSettingsView()
                .tabItem { Label("포트폴리오", systemImage: "chart.pie") }
            AlertSettingsView()
                .tabItem { Label("알림설정", systemImage: "bell") }
        }
        .frame(width: 580, height: 460)
        .padding()
    }
}

// MARK: - Shared Components

// React의 children prop과 동일. @ViewBuilder가 클로저 안의 뷰들을 하나의 Content로 합쳐준다.
struct SettingsTabContainer<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold()
            content
        }
        .padding([.horizontal, .bottom], 8)
    }
}

struct SettingsFormSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title).font(.headline)
            content
        }
    }
}

// MARK: - Watchlist

struct WatchlistSettingsView: View {
    @State private var items: [WatchlistItem] = []
    @State private var symbol = ""
    @State private var name = ""
    @State private var alias = ""
    @State private var group: WatchlistGroup = .watchlist

    var body: some View {
        SettingsTabContainer(title: "관심종목") {
            List {
                ForEach(items, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.alias ?? item.name).font(.body)
                            Text(item.symbol).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.group.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        Button {
                            deleteItem(item)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.bordered)

            SettingsFormSection(title: "종목 추가") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("종목코드").gridColumnAlignment(.trailing)
                        TextField("예: 005930", text: $symbol).frame(width: 120)
                        Text("종목명").gridColumnAlignment(.trailing)
                        TextField("예: 삼성전자", text: $name).frame(width: 120)
                    }
                    GridRow {
                        Text("별칭").gridColumnAlignment(.trailing)
                        TextField("선택사항", text: $alias).frame(width: 120)
                        Text("그룹").gridColumnAlignment(.trailing)
                        Picker("", selection: $group) {
                            ForEach([WatchlistGroup.watchlist, .longTerm, .shortTerm], id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                Button("추가") { addItem() }
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty ||
                              name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { loadItems() }
    }

    private func loadItems() {
        items = (try? DatabaseManager.shared.fetchWatchlist()) ?? []
    }

    private func addItem() {
        var item = WatchlistItem(
            id: nil,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            name: name.trimmingCharacters(in: .whitespaces),
            alias: alias.trimmingCharacters(in: .whitespaces).isEmpty ? nil : alias.trimmingCharacters(in: .whitespaces),
            group: group
        )
        try? DatabaseManager.shared.insert(&item)
        symbol = ""; name = ""; alias = ""
        loadItems()
        QuoteManager.shared.startPolling(symbols: items.map { $0.symbol })
    }

    private func deleteItem(_ item: WatchlistItem) {
        try? DatabaseManager.shared.delete(item)
        loadItems()
        QuoteManager.shared.startPolling(symbols: items.map { $0.symbol })
    }
}

// MARK: - Portfolio

struct PortfolioSettingsView: View {
    @State private var items: [PortfolioItem] = []
    @State private var symbol = ""
    @State private var name = ""
    @State private var averagePriceText = ""
    @State private var quantityText = ""

    var body: some View {
        SettingsTabContainer(title: "포트폴리오") {
            List {
                ForEach(items, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body)
                            Text(item.symbol).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("평균 \(NumberFormatter.decimal.string(from: NSNumber(value: item.averagePrice)) ?? "")원")
                                .font(.caption)
                            Text("\(item.quantity)주")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button {
                            deleteItem(item)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.bordered)

            SettingsFormSection(title: "종목 추가") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("종목코드").gridColumnAlignment(.trailing)
                        TextField("예: 005930", text: $symbol).frame(width: 120)
                        Text("종목명").gridColumnAlignment(.trailing)
                        TextField("예: 삼성전자", text: $name).frame(width: 120)
                    }
                    GridRow {
                        Text("평균매입가").gridColumnAlignment(.trailing)
                        TextField("원", text: $averagePriceText).frame(width: 120)
                        Text("수량").gridColumnAlignment(.trailing)
                        TextField("주", text: $quantityText).frame(width: 120)
                    }
                }

                Button("추가") { addItem() }
                    .disabled(!isFormValid)
            }
        }
        .onAppear { loadItems() }
    }

    private var isFormValid: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(averagePriceText) != nil &&
        Int(quantityText) != nil
    }

    private func loadItems() {
        items = (try? DatabaseManager.shared.fetchPortfolio()) ?? []
    }

    private func addItem() {
        guard let avg = Int(averagePriceText), let qty = Int(quantityText) else { return }
        var item = PortfolioItem(
            id: nil,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            name: name.trimmingCharacters(in: .whitespaces),
            averagePrice: avg,
            quantity: qty
        )
        try? DatabaseManager.shared.insert(&item)
        symbol = ""; name = ""; averagePriceText = ""; quantityText = ""
        loadItems()
    }

    private func deleteItem(_ item: PortfolioItem) {
        try? DatabaseManager.shared.delete(item)
        loadItems()
    }
}

// MARK: - Alert Settings

struct AlertSettingsView: View {
    @State private var conditions: [AlertCondition] = []
    @State private var symbol = ""
    @State private var triggerType: TriggerType = .targetPrice
    @State private var thresholdText = ""
    @State private var disableAfterTrigger = false
    @State private var cooldownMinutes = 60

    var body: some View {
        SettingsTabContainer(title: "알림설정") {
            List {
                ForEach(conditions, id: \.id) { condition in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(condition.symbol == "PORTFOLIO" ? "전체 포트폴리오" : condition.symbol).font(.body)
                                Text(condition.triggerType.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            Text("임계값: \(formatThreshold(condition)) · 쿨다운: \(condition.cooldownMinutes)분")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { condition.isActive },
                            set: { newValue in toggleCondition(condition, isActive: newValue) }
                        ))
                        .labelsHidden()
                        Button {
                            deleteCondition(condition)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.bordered)

            SettingsFormSection(title: "알림 추가") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("종목코드").gridColumnAlignment(.trailing)
                        if triggerType.isPortfolioLevel {
                            Text("전체 포트폴리오")
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                        } else {
                            TextField("예: 005930", text: $symbol).frame(width: 120)
                        }
                        Text("유형").gridColumnAlignment(.trailing)
                        Picker("", selection: $triggerType) {
                            ForEach([TriggerType.targetPrice, .stopLoss, .rateUp, .rateDown, .volumeSpike,
                                     .portfolioGain, .portfolioLoss, .portfolioGainRate, .portfolioLossRate],
                                    id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    GridRow {
                        Text("임계값").gridColumnAlignment(.trailing)
                        HStack(spacing: 4) {
                            TextField("값 입력", text: $thresholdText).frame(width: 80)
                            Text(triggerType.unit).foregroundStyle(.secondary)
                        }
                        Text("쿨다운").gridColumnAlignment(.trailing)
                        HStack(spacing: 4) {
                            TextField("분", value: $cooldownMinutes, format: .number).frame(width: 60)
                            Text("분").foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("").gridColumnAlignment(.trailing)
                        Toggle("트리거 후 자동 비활성화", isOn: $disableAfterTrigger)
                            .gridCellColumns(3)
                    }
                }

                Button("추가") { addCondition() }
                    .disabled(
                        (!triggerType.isPortfolioLevel && symbol.trimmingCharacters(in: .whitespaces).isEmpty)
                        || Double(thresholdText) == nil
                    )
            }
            .onChange(of: triggerType) { _, newType in
                if newType.isPortfolioLevel { symbol = "PORTFOLIO" }
            }
        }
        .onAppear { loadConditions() }
    }

    private func formatThreshold(_ c: AlertCondition) -> String {
        switch c.triggerType {
        case .targetPrice, .stopLoss, .portfolioGain, .portfolioLoss:
            return (NumberFormatter.decimal.string(from: NSNumber(value: Int(c.threshold))) ?? "") + "원"
        case .rateUp, .rateDown, .portfolioGainRate, .portfolioLossRate:
            return String(format: "%.1f%%", c.threshold)
        case .volumeSpike:
            return String(format: "%.1f배", c.threshold)
        }
    }

    private func loadConditions() {
        conditions = (try? DatabaseManager.shared.fetchAlertConditions()) ?? []
    }

    private func addCondition() {
        guard let threshold = Double(thresholdText) else { return }
        var condition = AlertCondition(
            id: nil,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            triggerType: triggerType,
            threshold: threshold,
            isActive: true,
            disableAfterTrigger: disableAfterTrigger,
            cooldownMinutes: cooldownMinutes,
            lastTriggeredAt: nil
        )
        try? DatabaseManager.shared.insert(&condition)
        symbol = ""; thresholdText = ""
        loadConditions()
    }

    private func toggleCondition(_ condition: AlertCondition, isActive: Bool) {
        var updated = condition
        updated.isActive = isActive
        try? DatabaseManager.shared.update(updated)
        loadConditions()
    }

    private func deleteCondition(_ condition: AlertCondition) {
        try? DatabaseManager.shared.delete(condition)
        loadConditions()
    }
}

// MARK: - Account

struct AccountSettingsView: View {
    @State private var appKey = ""
    @State private var appSecret = ""
    @State private var accountNumber = ""
    @State private var isMock = false

    @State private var isLoggedIn = false
    @State private var loginDate: Date? = nil
    @State private var savedAccountNumber = ""
    @State private var savedIsMock = false

    @State private var testStatus: TestStatus = .idle

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
            if isLoggedIn {
                loggedInView
            } else {
                loginFormView
            }
            DARTSettingsView()
            Spacer()
        }
        .onAppear { loadState() }
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

            HStack(spacing: 12) {
                Button("로그아웃", role: .destructive) { logout() }
                Spacer()
                Button("다른 계정으로 변경") { switchAccount() }
                    .foregroundStyle(.secondary)
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
        let storedKey = KeychainHelper.load(account: "kis.appKey") ?? ""
        isLoggedIn = !storedKey.isEmpty
        savedAccountNumber = KeychainHelper.load(account: "kis.accountNumber") ?? ""
        savedIsMock = UserDefaults.standard.bool(forKey: "KIS.isMock")
        if let ts = UserDefaults.standard.object(forKey: "KIS.loginDate") as? Date {
            loginDate = ts
        }
    }

    private func login() {
        KeychainHelper.save(appKey, account: "kis.appKey")
        KeychainHelper.save(appSecret, account: "kis.appSecret")
        KeychainHelper.save(accountNumber, account: "kis.accountNumber")
        UserDefaults.standard.set(isMock, forKey: "KIS.isMock")
        let now = Date()
        UserDefaults.standard.set(now, forKey: "KIS.loginDate")

        let creds = BrokerCredentials(
            appKey: appKey,
            appSecret: appSecret,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber
        )
        let adapter = KISAdapter(isMock: isMock)
        QuoteManager.shared.setAdapter(adapter)
        Task { try? await adapter.connect(credentials: creds) }

        withAnimation {
            savedAccountNumber = accountNumber
            savedIsMock = isMock
            loginDate = now
            isLoggedIn = true
            appKey = ""; appSecret = ""; accountNumber = ""
        }
    }

    private func logout() {
        KeychainHelper.delete(account: "kis.appKey")
        KeychainHelper.delete(account: "kis.appSecret")
        KeychainHelper.delete(account: "kis.accountNumber")
        UserDefaults.standard.removeObject(forKey: "KIS.loginDate")
        QuoteManager.shared.setAdapter(MockBrokerAdapter())
        withAnimation { isLoggedIn = false; loginDate = nil; testStatus = .idle }
    }

    private func switchAccount() {
        withAnimation { isLoggedIn = false; testStatus = .idle }
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

// MARK: - DART Settings

struct DARTDisclosureTypeOption: Identifiable {
    let code: String
    let name: String
    var id: String { code }

    static let all: [DARTDisclosureTypeOption] = [
        .init(code: "A", name: "정기공시"),
        .init(code: "B", name: "주요사항"),
        .init(code: "C", name: "발행공시"),
        .init(code: "D", name: "지분공시"),
        .init(code: "E", name: "기타공시"),
        .init(code: "I", name: "거래소공시"),
    ]
}

struct DARTSettingsView: View {
    @State private var isConfigured = false
    @State private var apiKeyInput = ""
    @State private var isSaving = false
    @State private var enabledTypes: Set<String> = []

    private static let allCodes = Set(DARTDisclosureTypeOption.all.map(\.code))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("DART 공시 알림").font(.headline)

            if isConfigured {
                dartConfiguredView
            } else {
                dartSetupView
            }
        }
        .onAppear {
            isConfigured = DARTManager.shared.isConfigured
            loadFilterTypes()
        }
    }

    private var dartConfiguredView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("공시 알림 활성화됨").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("삭제", role: .destructive) {
                    KeychainHelper.delete(account: "dart.apiKey")
                    DARTManager.shared.stop()
                    isConfigured = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .font(.caption)
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text("알림 받을 공시 종류").font(.subheadline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 6) {
                ForEach(DARTDisclosureTypeOption.all) { type in
                    Toggle(type.name, isOn: Binding(
                        get: { enabledTypes.contains(type.code) },
                        set: { isOn in
                            if isOn { enabledTypes.insert(type.code) }
                            else { enabledTypes.remove(type.code) }
                            saveFilterTypes()
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
            Text("선택하지 않으면 모든 종류를 알림으로 받습니다.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var dartSetupView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DART Open API 키를 입력하면 관심종목의 공시를 5분마다 확인합니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField("API 키 입력", text: $apiKeyInput)
                Button("저장") { saveKey() }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
    }

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isSaving = true
        KeychainHelper.save(key, account: "dart.apiKey")
        let symbols = (try? DatabaseManager.shared.fetchWatchlist().map { $0.symbol }) ?? []
        DARTManager.shared.start(symbols: symbols)
        apiKeyInput = ""
        isConfigured = true
        isSaving = false
    }

    private func loadFilterTypes() {
        let saved = UserDefaults.standard.stringArray(forKey: "DART.filterTypes") ?? []
        enabledTypes = saved.isEmpty ? Self.allCodes : Set(saved)
    }

    private func saveFilterTypes() {
        if enabledTypes == Self.allCodes {
            UserDefaults.standard.removeObject(forKey: "DART.filterTypes")
        } else {
            UserDefaults.standard.set(Array(enabledTypes), forKey: "DART.filterTypes")
        }
    }
}

private extension NumberFormatter {
    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
}
