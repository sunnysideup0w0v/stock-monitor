import SwiftUI

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

    @AppStorage("Screener.claudeEnabled") private var claudeEnabled = false
    @AppStorage("Screener.keepOnReopen") private var keepOnReopen = true
    @State private var showAnalysis = false
    @State private var analysisText = ""
    @State private var isAnalyzing = false
    @State private var analysisError: String?

    @State private var toastMessage: String?

    private let conditionsKey = "Screener.savedConditions"

    var body: some View {
        SettingsTabContainer(title: "종목 추천") {
            HStack(alignment: .top, spacing: 0) {
                conditionPanel
                    .padding(12)
                    .frame(width: 290)
                    .background(panelBackground)

                Divider()
                    .padding(.vertical, 4)

                resultPanel
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(panelBackground)
            }
        }
        .onAppear { loadState() }
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

            SettingsFormSection(title: "스크리닝 조건") {
                VStack(spacing: 6) {
                    ForEach($conditions) { $cond in
                        ConditionRowView(condition: $cond, sectors: sectors, markets: markets) {
                            conditions.removeAll { $0.id == cond.id }
                        }
                    }

                    Button {
                        conditions.append(ScreenerCondition(type: .priceRange))
                    } label: {
                        Label("조건 추가", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(.top, 4)
                }
            }

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

            Toggle(isOn: $keepOnReopen) {
                Text("창 재열 시 조건·결과 유지")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Spacer()
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
        saveConditions()
        isRunning = true
        errorMessage = nil
        Task {
            do {
                results = try ScreenerEngine.shared.run(conditions: conditions)
                lastRunDate = Date()
            } catch {
                errorMessage = "스크리닝 오류: \(error.localizedDescription)"
            }
            isRunning = false
        }
    }

    private func loadState() {
        universeCount = (try? DatabaseManager.shared.stockUniverseCount()) ?? 0
        universeUpdated = try? DatabaseManager.shared.stockUniverseLastUpdated()
        sectors = (try? ScreenerEngine.shared.availableSectors()) ?? []
        markets = (try? ScreenerEngine.shared.availableMarkets()) ?? []

        if keepOnReopen {
            loadConditions()
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
        Task {
            do {
                let r = try ScreenerEngine.shared.run(conditions: conditions)
                results = r
                if !r.isEmpty { lastRunDate = Date() }
            } catch { }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("", selection: $condition.type) {
                    ForEach(ScreenerCondition.ConditionType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: condition.type) { _, _ in
                    condition.minValue = nil
                    condition.maxValue = nil
                    condition.stringValue = nil
                    minText = ""
                    maxText = ""
                }

                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            if condition.type.usesStringValue {
                stringValueInput
            } else {
                numericRangeInput
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .onAppear {
            minText = condition.minValue.map { formatNumber($0) } ?? ""
            maxText = condition.maxValue.map { formatNumber($0) } ?? ""
        }
    }

    @ViewBuilder
    private var stringValueInput: some View {
        if condition.type == .sectorFilter {
            Picker("업종", selection: Binding(
                get: { condition.stringValue ?? "" },
                set: { condition.stringValue = $0 }
            )) {
                Text("선택").tag("")
                ForEach(sectors, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        } else if condition.type == .marketFilter {
            Picker("시장", selection: Binding(
                get: { condition.stringValue ?? "" },
                set: { condition.stringValue = $0 }
            )) {
                Text("전체").tag("")
                ForEach(markets, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
    }

    private var numericRangeInput: some View {
        HStack(spacing: 4) {
            if condition.type.supportsMin {
                TextField(condition.type.minPlaceholder, text: $minText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(minWidth: 60)
                    .onChange(of: minText) { _, v in condition.minValue = parseNumber(v) }
            }
            if condition.type.supportsMin && condition.type.supportsMax {
                Text("~").foregroundStyle(.secondary).font(.caption)
            }
            if condition.type.supportsMax {
                TextField(condition.type.maxPlaceholder, text: $maxText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(minWidth: 60)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 종목 분석", systemImage: "wand.and.stars")
                    .font(.title3).bold()
                Spacer()
                if isAnalyzing {
                    ProgressView().scaleEffect(0.8)
                }
                Button("닫기") { isPresented = false }
                    .buttonStyle(.borderless)
                    .disabled(isAnalyzing)
            }

            Divider()

            if let err = error {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if text.isEmpty && isAnalyzing {
                HStack {
                    ProgressView()
                    Text("분석 중...").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }

                if !text.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } label: {
                            Label("클립보드 복사", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }

            Text("본 분석은 투자 권고가 아닌 참고 목적입니다.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}
