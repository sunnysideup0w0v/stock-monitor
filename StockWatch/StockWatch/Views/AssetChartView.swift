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

    private var baseline: Double {
        showValue ? Double(snapshots.first?.totalValue ?? 0) : 0.0
    }

    // 연속점 간격이 threshold 초과 시 다른 segment로 분리
    private var gapThreshold: TimeInterval {
        switch period {
        case .day:   return 10 * 60      // 10분
        case .week:  return 6 * 3600     // 6시간
        case .month: return 2 * 86400    // 2일
        case .year:  return 10 * 86400   // 10일
        }
    }

    private var segments: [[PortfolioSnapshot]] {
        guard !snapshots.isEmpty else { return [] }
        var result: [[PortfolioSnapshot]] = [[snapshots[0]]]
        for i in 1..<snapshots.count {
            let gap = snapshots[i].timestamp.timeIntervalSince(snapshots[i - 1].timestamp)
            if gap > gapThreshold {
                result.append([snapshots[i]])
            } else {
                result[result.count - 1].append(snapshots[i])
            }
        }
        return result
    }

    // MARK: - Summary

    private var summary: (diff: Double, changePct: Double)? {
        guard let first = snapshots.first, let last = snapshots.last,
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

                    if let last = snapshots.last {
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
            Button(isMockGenerating ? "생성 중…" : "테스트 데이터 생성") {
                generateMockData()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.blue)
            .disabled(isMockGenerating)

            Button("테스트 데이터 삭제") {
                try? DatabaseManager.shared.deleteAllSnapshots()
                loadData()
                mockMessage = "삭제 완료"
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)

            if let msg = mockMessage {
                Text(msg).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chart Body

    private var chartBody: some View {
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                ForEach(seg, id: \.timestamp) { snap in
                    lineMarkFor(snap, seriesIdx: idx)
                }
            }
            RuleMark(y: .value("기준", baseline))
                .foregroundStyle(.gray.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
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
    private func lineMarkFor(_ snap: PortfolioSnapshot, seriesIdx: Int) -> some ChartContent {
        let yLabel = showValue ? "금액" : "수익률"
        LineMark(
            x: .value("시간", snap.timestamp),
            y: .value(yLabel, chartValue(snap)),
            series: .value("s", seriesIdx)
        )
        .foregroundStyle(.blue)
        .interpolationMethod(.monotone)
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
        if mockMessage != nil { mockMessage = nil }
    }

    // 30일치 Mock 스냅샷 생성 (평일 09:00~15:30, 5분 간격)
    // 총평가액 기준: 시작 10,000,000원 (매입원가 9,500,000원 가정), 랜덤 워크
    private func generateMockData() {
        isMockGenerating = true
        Task.detached {
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
                    batch.append(PortfolioSnapshot(id: nil, timestamp: ts, totalValue: value, totalGain: gain, gainPct: gainPct))
                    minuteCursor += 5
                }
            }

            try? DatabaseManager.shared.insertSnapshots(batch)

            await MainActor.run {
                isMockGenerating = false
                mockMessage = "\(batch.count)건 생성 완료"
                loadData()
            }
        }
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
