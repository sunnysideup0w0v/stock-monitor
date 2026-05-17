import SwiftUI
import MarkdownUI

struct ScreenerView: View {
    @State private var conditions: [ScreenerCondition] = []
    @State private var results: [StockUniverseItem] = []
    @State private var isRunning = false
    @State private var lastRunDate: Date?
    @State private var errorMessage: String?
    @State private var universeCount = 0
    @State private var universeUpdated: Date?
    @State private var sectors: [String] = []
    @State private var markets: [String] = []

    @AppStorage(UserDefaultsKey.screenerClaudeEnabled) private var claudeEnabled = false
    @AppStorage(UserDefaultsKey.screenerKeepOnReopen) private var keepOnReopen = true
    @State private var hasRun = false
    @State private var showAnalysis = false
    @State private var analysisText = ""
    @State private var isAnalyzing = false
    @State private var analysisError: String?

    @State private var toastMessage: String?

    private let conditionsKey = UserDefaultsKey.screenerSavedConditions

    var body: some View {
        SettingsTabContainer(title: "종목 검색") {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    conditionPanel
                        .padding(12)
                        .frame(maxHeight: .infinity)
                        .background(panelBackground)

                    Toggle(isOn: $keepOnReopen) {
                        Text("설정 창을 다시 열 때 조건·결과 유지")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .padding(.leading, 4)
                }
                .frame(width: 290)

                resultPanel
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(panelBackground)
            }
        }
        .onAppear {
            AppLogger.log("ScreenerView appeared", category: "Screener")
            hasRun = false
            loadState()
        }
        .onDisappear {
            AppLogger.log("ScreenerView disappeared (hasRun=\(hasRun))", category: "Screener")
            if hasRun {
                cleanEmptyConditions()
                saveConditions()
            }
            // hasRun == false 시 저장하지 않음 → 다음 onAppear에서 마지막 저장값 복원
        }
        .sheet(isPresented: $showAnalysis) {
            AnalysisSheetView(
                text: $analysisText,
                isAnalyzing: $isAnalyzing,
                error: $analysisError,
                isPresented: $showAnalysis
            )
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    // MARK: - Condition Panel

    private var conditionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            dataStatusRow

            Divider()

            Text("스크리닝 조건").font(.headline)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach($conditions) { $cond in
                        ConditionRowView(condition: $cond, sectors: sectors, markets: markets) {
                            conditions.removeAll { $0.id == cond.id }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
                )
            }

            Button {
                conditions.append(ScreenerCondition(type: .priceRange))
            } label: {
                Label("조건 추가", systemImage: "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Button {
                runScreener()
            } label: {
                if isRunning {
                    HStack { ProgressView().scaleEffect(0.7); Text("스크리닝 중...") }
                } else {
                    Label("스크리닝 실행", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || conditions.isEmpty)
            .frame(maxWidth: .infinity)

            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var dataStatusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if universeCount > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("전종목 데이터 \(universeCount.formatted())개")
                        .font(.callout)
                }
                if let date = universeUpdated {
                    Text("기준: \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("KRX 데이터 수집 중...").font(.callout)
                }
                Text("계좌 연결 탭에서 상태를 확인하세요")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Result Panel

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(results.isEmpty && lastRunDate == nil ? "결과가 여기에 표시됩니다" : "결과 \(results.count)개")
                    .font(.headline)
                Spacer()
                if let date = lastRunDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if results.isEmpty && lastRunDate == nil {
                emptyPlaceholder
            } else if results.isEmpty {
                Text("조건에 맞는 종목이 없습니다")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(results.enumerated()), id: \.element.symbol) { idx, item in
                                ScreenerResultRowView(item: item, rank: idx + 1) { name in
                                    showToast("\(name) 관심종목에 추가됨")
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    if let msg = toastMessage {
                        ToastBannerView(message: msg)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: toastMessage)

                if claudeEnabled {
                    Button {
                        startAnalysis()
                    } label: {
                        Label("AI 분석", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("조건을 설정하고 스크리닝을 실행하세요")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Actions

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            toastMessage = nil
        }
    }

    private func startAnalysis() {
        analysisText = ""
        analysisError = nil
        isAnalyzing = true
        showAnalysis = true
        let snapshot = (conditions: conditions, results: results)
        Task {
            do {
                try await ClaudeAnalyzer.shared.analyze(
                    conditions: snapshot.conditions,
                    results: snapshot.results
                ) { @MainActor token in
                    analysisText += token
                }
            } catch {
                analysisError = error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    private func runScreener() {
        guard !conditions.isEmpty else { return }
        cleanEmptyConditions()
        guard !conditions.isEmpty else { return }
        saveConditions()
        hasRun = true
        isRunning = true
        errorMessage = nil
        AppLogger.log("runScreener: conditions=\(conditions.count)", category: "Screener")
        Task {
            do {
                results = try ScreenerEngine.shared.run(conditions: conditions)
                lastRunDate = Date()
                AppLogger.log("runScreener: completed results=\(results.count)", category: "Screener")
            } catch {
                errorMessage = "스크리닝 오류: \(error.localizedDescription)"
                AppLogger.log("runScreener: error=\(error)", level: .error, category: "Screener")
            }
            isRunning = false
        }
    }

    private func cleanEmptyConditions() {
        conditions = conditions.filter { cond in
            if cond.type.usesStringValue {
                return !(cond.stringValue?.isEmpty ?? true)
            } else {
                return cond.minValue != nil || cond.maxValue != nil
            }
        }
    }

    private func loadState() {
        universeCount = (try? DatabaseManager.shared.stockUniverseCount()) ?? 0
        universeUpdated = try? DatabaseManager.shared.stockUniverseLastUpdated()
        sectors = (try? ScreenerEngine.shared.availableSectors()) ?? []
        markets = (try? ScreenerEngine.shared.availableMarkets()) ?? []

        if keepOnReopen {
            loadConditions()
            cleanEmptyConditions()
            if !conditions.isEmpty {
                autoRunScreener()
            }
        } else {
            conditions = []
            results = []
            lastRunDate = nil
        }
    }

    private func autoRunScreener() {
        AppLogger.log("autoRunScreener: conditions=\(conditions.count)", category: "Screener")
        Task {
            do {
                let r = try ScreenerEngine.shared.run(conditions: conditions)
                results = r
                if !r.isEmpty { lastRunDate = Date() }
                AppLogger.log("autoRunScreener: completed results=\(r.count)", category: "Screener")
            } catch {
                AppLogger.log("autoRunScreener: error=\(error)", level: .error, category: "Screener")
            }
        }
    }

    private func saveConditions() {
        if let data = try? JSONEncoder().encode(conditions) {
            UserDefaults.standard.set(data, forKey: conditionsKey)
        }
    }

    private func loadConditions() {
        guard let data = UserDefaults.standard.data(forKey: conditionsKey),
              let saved = try? JSONDecoder().decode([ScreenerCondition].self, from: data)
        else { return }
        conditions = saved
    }
}

// MARK: - Condition Row

private struct ConditionRowView: View {
    @Binding var condition: ScreenerCondition
    let sectors: [String]
    let markets: [String]
    let onDelete: () -> Void

    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 7) {
                Picker("", selection: $condition.type) {
                    ForEach(ScreenerCondition.ConditionType.allCases, id: \.self) { t in
                        Text(t.shortName).tag(t)
                    }
                }
                .labelsHidden()
                .onChange(of: condition.type) { _, _ in
                    condition.minValue = nil
                    condition.maxValue = nil
                    condition.stringValue = nil
                    minText = ""
                    maxText = ""
                }

                if condition.type.usesStringValue {
                    stringValueInput
                } else {
                    numericRangeInput
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            minText = condition.minValue.map { formatNumber($0) } ?? ""
            maxText = condition.maxValue.map { formatNumber($0) } ?? ""
        }
    }

    @ViewBuilder
    private var stringValueInput: some View {
        if condition.type == .sectorFilter {
            if sectors.isEmpty {
                Text("업종 데이터 없음 — KRX API 키 필요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                checkboxGroup(options: sectors, columns: 1)
            }
        } else if condition.type == .marketFilter {
            checkboxGroup(options: markets.isEmpty ? ["KOSPI", "KOSDAQ"] : markets, columns: 2)
        } else if condition.type == .instrumentType {
            checkboxGroup(options: ["주식", "ETF"], columns: 2)
        }
    }

    @ViewBuilder
    private func checkboxGroup(options: [String], columns: Int) -> some View {
        let selected = selectedSet
        if columns == 2 {
            HStack(spacing: 12) {
                ForEach(options, id: \.self) { opt in
                    checkboxButton(opt, selected: selected)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(options, id: \.self) { opt in
                    checkboxButton(opt, selected: selected)
                }
            }
        }
    }

    private func checkboxButton(_ option: String, selected: Set<String>) -> some View {
        Button { toggleOption(option) } label: {
            HStack(spacing: 5) {
                Image(systemName: selected.contains(option) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected.contains(option) ? Color.accentColor : .secondary)
                    .font(.system(size: 14))
                Text(option)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private var selectedSet: Set<String> {
        Set((condition.stringValue ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func toggleOption(_ option: String) {
        var sel = selectedSet
        if sel.contains(option) { sel.remove(option) } else { sel.insert(option) }
        condition.stringValue = sel.sorted().joined(separator: ",")
    }

    private var numericRangeInput: some View {
        HStack(spacing: 4) {
            if condition.type.supportsMin {
                TextField(condition.type.minPlaceholder, text: $minText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .onChange(of: minText) { _, v in condition.minValue = parseNumber(v) }
            }
            if condition.type.supportsMin && condition.type.supportsMax {
                Text("~").foregroundStyle(.secondary).font(.caption)
            }
            if condition.type.supportsMax {
                TextField(condition.type.maxPlaceholder, text: $maxText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .onChange(of: maxText) { _, v in condition.maxValue = parseNumber(v) }
            }
            if !condition.type.unit.isEmpty {
                Text(condition.type.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    private func parseNumber(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ""))
    }

    private func formatNumber(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }
}

// MARK: - Result Row

private struct ScreenerResultRowView: View {
    let item: StockUniverseItem
    let rank: Int
    let onAdd: (String) -> Void
    @State private var added = false

    private var changeRate: Double {
        guard item.open > 0 else { return 0 }
        return Double(item.close - item.open) / Double(item.open) * 100
    }

    private var priceStr: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return (f.string(from: NSNumber(value: item.close)) ?? "\(item.close)") + "원"
    }

    private var changeRateStr: String {
        let r = changeRate
        return (r >= 0 ? "+" : "") + String(format: "%.2f%%", r)
    }

    private var changeRateColor: Color { changeRate >= 0 ? .red : .blue }

    private var marketCapStr: String {
        let 억 = item.marketCap / 100
        if 억 >= 10000 { return String(format: "%.1f조", Double(억) / 10000) }
        return "\(억.formatted())억"
    }

    private var isKospi: Bool { item.market == "KOSPI" || item.market.contains("코스피") }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.name).font(.callout).fontWeight(.medium)
                    Text(item.symbol).font(.caption2).foregroundStyle(.secondary)
                    Text(item.market)
                        .font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(isKospi ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                        .foregroundStyle(isKospi ? Color.blue : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                HStack(spacing: 8) {
                    Text(priceStr).font(.caption).monospacedDigit()
                    Text(changeRateStr).font(.caption).foregroundStyle(changeRateColor).monospacedDigit()
                    Text(marketCapStr).font(.caption).foregroundStyle(.secondary)
                    if let per = item.per {
                        Text("PER \(String(format: "%.1f", per))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let sector = item.sector {
                        Text(sector).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button {
                addToWatchlist()
            } label: {
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.caption)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(added)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func addToWatchlist() {
        var w = WatchlistItem(symbol: item.symbol, name: item.name, alias: nil, group: .watchlist)
        try? DatabaseManager.shared.insert(&w)
        added = true
        onAdd(item.name)
    }
}

// MARK: - Toast Banner

private struct ToastBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.75), in: Capsule())
        .padding(.bottom, 8)
    }
}

// MARK: - Analysis Sheet

private struct AnalysisSheetView: View {
    @Binding var text: String
    @Binding var isAnalyzing: Bool
    @Binding var error: String?
    @Binding var isPresented: Bool

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if error == nil {
                HStack {
                    Label("AI 종목 분석", systemImage: "wand.and.stars")
                        .font(.title3).bold()
                    Spacer()
                    Button("닫기") { isPresented = false }
                        .buttonStyle(.borderless)
                        .disabled(isAnalyzing)
                }
                Divider()
            }

            if let err = error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text(err)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button("닫기") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if isAnalyzing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("AI가 종목을 분석하고 있습니다...")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    Markdown(text)
                        .textSelection(.enabled)
                        .markdownTheme(.analysis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)

                if !text.isEmpty {
                    HStack {
                        Text("본 분석은 투자 권고가 아닌 참고 목적입니다.")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            withAnimation { copied = true }
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation { copied = false }
                            }
                        } label: {
                            Label(
                                copied ? "복사됨" : "클립보드 복사",
                                systemImage: copied ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(copied ? .green : .secondary)
                        .animation(.default, value: copied)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}

// MARK: - MarkdownUI 커스텀 테마

extension MarkdownUI.Theme {
    // Theme.gitHub 기반 — 헤딩 크기·굵기·색상을 포함한 기본 스타일 상속
    // Swift 6 strict concurrency: 블록 클로저 내부에서 markdownTextStyle 사용 불가
    // → 블록 스타일은 표준 SwiftUI 모디파이어만 사용
    static var analysis: Theme {
        Theme.gitHub
            .text {
                FontSize(12.5)  // 이모지 포함 전체 텍스트 사이즈 축소
            }
            .strong {
                FontWeight(.semibold)
                ForegroundColor(Color.orange)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(11.5)
                BackgroundColor(Color.primary.opacity(0.07))
            }
            .blockquote { config in
                config.label
                    .padding(.vertical, 6)
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .background(Color.accentColor.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .frame(width: 3)
                            .foregroundStyle(Color.accentColor.opacity(0.5))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .codeBlock { config in
                config.label
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
    }
}
