import SwiftUI
import Charts

struct AssetChartView: View {
    @State private var period: ChartPeriod = .day
    @State private var selectedDate: Date = Date()
    @State private var showValue: Bool = true   // true=금액, false=수익률
    @State private var snapshots: [PortfolioSnapshot] = []

    enum ChartPeriod: String, CaseIterable {
        case day   = "일"
        case week  = "주"
        case month = "월"
        case year  = "연"
    }

    // MARK: - Date Range

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        switch period {
        case .day:
            let start = cal.startOfDay(for: selectedDate)
            return (start, cal.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
            comps.weekday = 2 // 월요일 기준
            let start = cal.date(from: comps) ?? cal.startOfDay(for: selectedDate)
            return (start, cal.date(byAdding: .day, value: 7, to: start)!)
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate))!
            return (start, cal.date(byAdding: .month, value: 1, to: start)!)
        case .year:
            let start = cal.date(from: cal.dateComponents([.year], from: selectedDate))!
            return (start, cal.date(byAdding: .year, value: 1, to: start)!)
        }
    }

    private var dateRangeLabel: String {
        let fmt = DateFormatter()
        switch period {
        case .day:
            fmt.dateFormat = "yyyy.MM.dd"
            return fmt.string(from: selectedDate)
        case .week:
            let (start, end) = dateRange
            fmt.dateFormat = "MM.dd"
            let endDay = Calendar.current.date(byAdding: .day, value: -1, to: end)!
            return "\(fmt.string(from: start)) ~ \(fmt.string(from: endDay))"
        case .month:
            fmt.dateFormat = "yyyy년 MM월"
            return fmt.string(from: selectedDate)
        case .year:
            fmt.dateFormat = "yyyy년"
            return fmt.string(from: selectedDate)
        }
    }

    private func stepDate(_ direction: Int) {
        let cal = Calendar.current
        switch period {
        case .day:   selectedDate = cal.date(byAdding: .day,   value: direction,      to: selectedDate) ?? selectedDate
        case .week:  selectedDate = cal.date(byAdding: .day,   value: direction * 7,  to: selectedDate) ?? selectedDate
        case .month: selectedDate = cal.date(byAdding: .month, value: direction,      to: selectedDate) ?? selectedDate
        case .year:  selectedDate = cal.date(byAdding: .year,  value: direction,      to: selectedDate) ?? selectedDate
        }
    }

    // MARK: - Chart Data

    private func chartValue(_ s: PortfolioSnapshot) -> Double {
        showValue ? Double(s.totalValue) : s.gainPct
    }

    // 일 뷰: raw intraday 데이터 그대로
    // 주/월 뷰: 날짜별 마지막 스냅샷(일별 종가)으로 집계
    // 연 뷰: 월별 마지막 스냅샷으로 집계
    private var displaySnapshots: [PortfolioSnapshot] {
        switch period {
        case .day:   return snapshots
        case .week, .month: return dailyAggregated(snapshots)
        case .year:  return monthlyAggregated(snapshots)
        }
    }

    private func dailyAggregated(_ snaps: [PortfolioSnapshot]) -> [PortfolioSnapshot] {
        let cal = Calendar.current
        var byDay: [Date: PortfolioSnapshot] = [:]
        for snap in snaps {
            let key = cal.startOfDay(for: snap.timestamp)
            if let existing = byDay[key] {
                if snap.timestamp > existing.timestamp { byDay[key] = snap }
            } else {
                byDay[key] = snap
            }
        }
        return byDay.values.sorted { $0.timestamp < $1.timestamp }
    }

    private func monthlyAggregated(_ snaps: [PortfolioSnapshot]) -> [PortfolioSnapshot] {
        let cal = Calendar.current
        var byMonth: [Date: PortfolioSnapshot] = [:]
        for snap in snaps {
            let key = cal.date(from: cal.dateComponents([.year, .month], from: snap.timestamp)) ?? snap.timestamp
            if let existing = byMonth[key] {
                if snap.timestamp > existing.timestamp { byMonth[key] = snap }
            } else {
                byMonth[key] = snap
            }
        }
        return byMonth.values.sorted { $0.timestamp < $1.timestamp }
    }

    private var baseline: Double {
        showValue ? Double(displaySnapshots.first?.totalValue ?? 0) : 0.0
    }

    // 일 뷰: 10분 (intraday gap)
    // 주/월 뷰: 4일 (주말 2일 + 여유 — 평일 연속 일별 데이터를 끊지 않음)
    // 연 뷰: 45일 (월별 데이터, 한 달 간격 브릿지)
    private var gapThreshold: TimeInterval {
        switch period {
        case .day:          return 10 * 60
        case .week, .month: return 4 * 86400
        case .year:         return 45 * 86400
        }
    }

    private var segments: [[PortfolioSnapshot]] {
        let data = displaySnapshots
        guard !data.isEmpty else { return [] }
        var result: [[PortfolioSnapshot]] = [[data[0]]]
        for i in 1..<data.count {
            let gap = data[i].timestamp.timeIntervalSince(data[i - 1].timestamp)
            if gap > gapThreshold {
                result.append([data[i]])
            } else {
                result[result.count - 1].append(data[i])
            }
        }
        return result
    }

    // MARK: - Summary

    private var summary: (diff: Double, changePct: Double)? {
        guard let first = displaySnapshots.first, let last = displaySnapshots.last,
              first.id != last.id else { return nil }
        let a = chartValue(first), b = chartValue(last)
        let diff = b - a
        let pct  = a != 0 ? diff / abs(a) * 100 : 0
        return (diff, pct)
    }

    @State private var isMockGenerating = false
    @State private var mockMessage: String? = nil

    // MARK: - Body

    var body: some View {
        SettingsTabContainer(title: "자산 차트") {
            // 기간 컨트롤
            HStack(spacing: 8) {
                Picker("", selection: $period) {
                    ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Button { stepDate(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(dateRangeLabel)
                    .font(.caption).frame(minWidth: 140, alignment: .center)
                Button { stepDate(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                Button("오늘") { selectedDate = Date() }
                    .buttonStyle(.borderless).font(.caption)

                Spacer()

                Picker("", selection: $showValue) {
                    Text("금액").tag(true)
                    Text("수익률").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }

            // 요약
            if let s = summary {
                HStack(spacing: 12) {
                    Group {
                        if showValue {
                            Text((s.diff >= 0 ? "+" : "") + fmt(Int(s.diff)) + "원")
                                .font(.title3).bold()
                        } else {
                            Text(String(format: "%+.2f%%p", s.diff))
                                .font(.title3).bold()
                        }
                    }
                    .foregroundStyle(s.diff >= 0 ? .green : .red)

                    Text(String(format: "%+.2f%%", s.changePct))
                        .font(.subheadline).foregroundStyle(.secondary)

                    Spacer()

                    if let last = displaySnapshots.last {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(showValue
                                 ? fmt(last.totalValue) + "원"
                                 : String(format: "%.2f%%", last.gainPct))
                            .font(.subheadline).fontDesign(.monospaced)
                            Text("현재").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            // 차트
            if snapshots.isEmpty {
                VStack(spacing: 10) {
                    Text("선택한 기간에 데이터가 없습니다")
                        .font(.caption).foregroundStyle(.secondary)
                    mockDataControls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chartBody
                    .frame(height: 200)
                mockDataControls
            }
        }
        .onChange(of: period)       { _, _ in loadData() }
        .onChange(of: selectedDate) { _, _ in loadData() }
        .onChange(of: showValue)    { _, _ in }
        .onAppear { loadData() }
    }

    @ViewBuilder
    private var mockDataControls: some View {
        HStack(spacing: 8) {
            if isMockGenerating {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                Text("생성 중…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("테스트 데이터 생성 (30일)") { generateMockData() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.blue)
            }

            Button("삭제") {
                try? DatabaseManager.shared.deleteAllSnapshots()
                mockMessage = "삭제 완료"
                loadData()
            }
            .buttonStyle(.borderless).font(.caption).foregroundStyle(.red)
            .disabled(isMockGenerating)

            if let msg = mockMessage {
                Text(msg).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chart Body

    private var overallColor: Color {
        guard let last = displaySnapshots.last else { return .blue }
        return chartValue(last) >= baseline ? .green : .red
    }

    // 타입 추론 타임아웃 방지: 각 mark 종류를 별도 @ChartContentBuilder 프로퍼티로 분리
    @ChartContentBuilder private var areaAboveContent: some ChartContent {
        ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
            ForEach(seg, id: \.timestamp) { snap in
                areaAboveMark(snap, seriesIdx: idx)
            }
        }
    }

    @ChartContentBuilder private var areaBelowContent: some ChartContent {
        ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
            ForEach(seg, id: \.timestamp) { snap in
                areaBelowMark(snap, seriesIdx: idx)
            }
        }
    }

    @ChartContentBuilder private var lineContent: some ChartContent {
        ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
            ForEach(seg, id: \.timestamp) { snap in
                lineMarkFor(snap, seriesIdx: idx)
            }
        }
    }

    private var chartBody: some View {
        Chart {
            areaAboveContent   // 기준선 위 초록 면적
            areaBelowContent   // 기준선 아래 빨간 면적
            lineContent        // 선 (면적 위에 렌더)
            RuleMark(y: .value("기준", baseline))
                .foregroundStyle(.gray.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .trailing, alignment: .trailing) {
                    Text(showValue ? "기준" : "0%")
                        .font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) {
                AxisGridLine(); AxisTick()
                AxisValueLabel(format: xAxisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { yLabel(v) }
            }
        }
        .chartLegend(.hidden)
    }

    @ChartContentBuilder
    private func areaAboveMark(_ snap: PortfolioSnapshot, seriesIdx: Int) -> some ChartContent {
        let y = chartValue(snap)
        let base = baseline
        AreaMark(
            x: .value("시간", snap.timestamp),
            yStart: .value("기준", base),
            yEnd: .value("값", max(y, base)),
            series: .value("up", seriesIdx)
        )
        .foregroundStyle(.green.opacity(0.15))
        .interpolationMethod(.monotone)
    }

    @ChartContentBuilder
    private func areaBelowMark(_ snap: PortfolioSnapshot, seriesIdx: Int) -> some ChartContent {
        let y = chartValue(snap)
        let base = baseline
        AreaMark(
            x: .value("시간", snap.timestamp),
            yStart: .value("값", min(y, base)),
            yEnd: .value("기준", base),
            series: .value("dn", seriesIdx)
        )
        .foregroundStyle(.red.opacity(0.15))
        .interpolationMethod(.monotone)
    }

    @ChartContentBuilder
    private func lineMarkFor(_ snap: PortfolioSnapshot, seriesIdx: Int) -> some ChartContent {
        LineMark(
            x: .value("시간", snap.timestamp),
            y: .value(showValue ? "금액" : "수익률", chartValue(snap)),
            series: .value("l", seriesIdx)
        )
        .foregroundStyle(overallColor)
        .interpolationMethod(.monotone)
        .lineStyle(StrokeStyle(lineWidth: 1.5))
    }

    @ViewBuilder
    private func yLabel(_ v: AxisValue) -> some View {
        if let d = v.as(Double.self) {
            if showValue { Text(fmtShort(Int(d))) }
            else         { Text(String(format: "%.1f%%", d)) }
        }
    }

    // MARK: - Helpers

    private var xAxisFormat: Date.FormatStyle {
        switch period {
        case .day:   return .dateTime.hour().minute()
        case .week:  return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .year:  return .dateTime.month(.abbreviated)
        }
    }

    private func loadData() {
        let (start, end) = dateRange
        snapshots = (try? DatabaseManager.shared.fetchSnapshots(from: start, to: end)) ?? []
    }

    // Task.detached 대신 Task { } 사용: @MainActor context 상속 → @State 직접 접근 가능
    // buildMockBatch()는 static으로 분리해 actor isolation 회피
    private func generateMockData() {
        guard !isMockGenerating else { return }
        isMockGenerating = true
        mockMessage = nil

        Task {
            await Task.yield()  // UI가 로딩 상태를 렌더링할 틈을 줌

            let batch = Self.buildMockBatch()
            do {
                try DatabaseManager.shared.insertSnapshots(batch)
                mockMessage = "✓ \(batch.count)건 생성됨 — 주 또는 월 뷰로 확인하세요"
            } catch {
                mockMessage = "생성 실패: \(error.localizedDescription)"
            }
            isMockGenerating = false
            loadData()
        }
    }

    private static func buildMockBatch() -> [PortfolioSnapshot] {
        let cal = Calendar.current
        let now = Date()
        let baseCost = 9_500_000
        var value = 10_000_000
        var batch: [PortfolioSnapshot] = []

        for dayOffset in stride(from: -29, through: 0, by: 1) {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = cal.component(.weekday, from: day)
            guard weekday != 1 && weekday != 7 else { continue }

            var minuteCursor = 9 * 60
            while minuteCursor <= 15 * 60 + 30 {
                let h = minuteCursor / 60, m = minuteCursor % 60
                guard let ts = cal.date(bySettingHour: h, minute: m, second: 0, of: day),
                      ts <= now else { minuteCursor += 5; continue }

                let delta = Double.random(in: -0.003...0.003)
                value = max(6_000_000, Int(Double(value) * (1 + delta)))
                let gain = value - baseCost
                let gainPct = Double(gain) / Double(baseCost) * 100
                batch.append(PortfolioSnapshot(id: nil, timestamp: ts,
                                               totalValue: value, totalGain: gain, gainPct: gainPct))
                minuteCursor += 5
            }
        }
        return batch
    }

    private func fmt(_ v: Int) -> String {
        NumberFormatter.decimal.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // Y축 레이블용 축약 표시 (1,000,000 → 100만)
    private func fmtShort(_ v: Int) -> String {
        let abs = Swift.abs(v)
        let sign = v < 0 ? "-" : ""
        if abs >= 100_000_000 { return "\(sign)\(abs / 100_000_000)억" }
        if abs >= 10_000      { return "\(sign)\(abs / 10_000)만" }
        return fmt(v)
    }
}

private extension NumberFormatter {
    static let decimal: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()
}
