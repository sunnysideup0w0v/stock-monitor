import SwiftUI
import Charts

struct AssetChartView: View {
    @State private var period: ChartPeriod = .day
    @State private var selectedDate: Date = Date()
    @State private var showValue: Bool = true   // true=금액, false=수익률
    @State private var snapshots: [PortfolioSnapshot] = []
    @State private var zoomLevel: Int = 1               // 0=wide … 4=fine. 기본 1 (넓은 단위)
    @State private var storedMasterStep: Double = 1_000_000 // loadData() 때 갱신
    private let dayWindowHours: Int = 2                  // 일 뷰 가로 스크롤 표시 구간(h)
    @State private var scrollAnchor: Date = Date()      // chartScrollPosition 바인딩

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

    // 일 뷰 스크롤 가능 전체 구간: 장 시작(09:00)~장 마감(15:30)
    private var dayXDomain: ClosedRange<Date> {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: selectedDate)
        comps.hour = 9; comps.minute = 0; comps.second = 0
        let open  = cal.date(from: comps) ?? dateRange.start
        comps.hour = 15; comps.minute = 30
        let close = cal.date(from: comps) ?? dateRange.end
        return open...close
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

    // MARK: - Y Axis Unit & Domain

    // storedMasterStep 접근자 (항상 일별 intraday 변동폭 기준으로 유지됨)
    private var masterStep: Double { storedMasterStep }

    // 기간이 바뀌어도 단위가 일관되도록 일별 intraday 변동폭의 중간값으로 계산
    // snapshots(raw)를 날짜별로 그룹핑 → 각 날의 고저 차이 → 중간값 → niceStep
    private func computeMasterStep() -> Double {
        guard !snapshots.isEmpty else { return showValue ? 1_000_000 : 1 }
        let cal = Calendar.current
        var byDay: [Date: (lo: Double, hi: Double)] = [:]
        for snap in snapshots {
            let day = cal.startOfDay(for: snap.timestamp)
            let v   = chartValue(snap)
            if let r = byDay[day] { byDay[day] = (min(r.lo, v), max(r.hi, v)) }
            else                  { byDay[day] = (v, v) }
        }
        var spans = byDay.values.map { $0.hi - $0.lo }.filter { $0 > 0 }
        guard !spans.isEmpty else { return showValue ? 1_000_000 : 1 }
        spans.sort()
        let median  = spans[spans.count / 2]
        let minSpan = showValue ? 100_000.0 : 0.1
        return niceStep(max(median, minSpan) / 4)
    }

    // 5단계 프리셋: masterStep의 [50×, 10×, 5×, 2×, 1×]
    // 예) masterStep=100만 → [5000만, 1000만, 500만, 200만, 100만]
    private var stepPresets: [Double] {
        let base = masterStep
        return [base * 50, base * 10, base * 5, base * 2, base]
    }

    private var currentStep: Double { stepPresets[min(zoomLevel, stepPresets.count - 1)] }

    // 도메인: 데이터 중심으로부터 ±(step × 2.5) — 항상 5칸 고정, 단위가 바뀔수록 범위 축소
    private var yDomain: ClosedRange<Double> {
        let values = displaySnapshots.map { chartValue($0) }
        guard !values.isEmpty else { return showValue ? 0...100_000_000 : -5...5 }
        let center = ((values.min()! + values.max()!) / 2)
        let half   = currentStep * 2.5
        return (center - half)...(center + half)
    }

    // currentStep 간격, 0 기준 정렬 눈금
    private var yAxisValues: [Double] {
        let step = currentStep
        let lo = yDomain.lowerBound, hi = yDomain.upperBound
        guard step > 0, hi > lo else { return [] }
        let start = ceil(lo / step) * step
        var values: [Double] = []
        var v = start
        while v <= hi + step * 0.001 { values.append(v); v += step }
        return values
    }

    // 버튼 옆에 표시할 현재 단위 레이블
    private var yStepLabel: String {
        showValue ? fmtShort(Int(currentStep)) : String(format: "%.2g%%", currentStep)
    }

    private func niceStep(_ rough: Double) -> Double {
        guard rough > 0 else { return 1 }
        let mag = pow(10.0, floor(log10(rough)))
        let f = rough / mag
        if f < 1.5 { return 1 * mag }
        if f < 3.5 { return 2 * mag }
        if f < 7.5 { return 5 * mag }
        return 10 * mag
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

                // Y축 단위 선택
                HStack(spacing: 2) {
                    Button { zoomLevel = max(0, zoomLevel - 1) } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoomLevel <= 0 || displaySnapshots.isEmpty)

                    Text(yStepLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 56, alignment: .center)

                    Button { zoomLevel = min(4, zoomLevel + 1) } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoomLevel >= 4 || displaySnapshots.isEmpty)
                }

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
                Text("선택한 기간에 데이터가 없습니다")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chartBody
                    .frame(height: 200)
            }
        }
        .onChange(of: period)        { _, _ in zoomLevel = 1; loadData() }
        .onChange(of: selectedDate)  { _, _ in loadData() }
        .onChange(of: showValue)     { _, _ in storedMasterStep = computeMasterStep(); zoomLevel = 1 }
        .onAppear { loadData() }
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

    private var baseChart: some View {
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
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic) {
                AxisGridLine(); AxisTick()
                AxisValueLabel(format: xAxisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(values: yAxisValues) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { yLabel(v) }
            }
        }
        .chartLegend(.hidden)
    }

    @ViewBuilder
    private var chartBody: some View {
        if period == .day {
            baseChart
                .chartXScale(domain: dayXDomain)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: Double(dayWindowHours) * 3600)
                .chartScrollPosition(x: $scrollAnchor)
        } else {
            baseChart
        }
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

    private func updateScrollAnchor() {
        guard period == .day, dayWindowHours > 0 else { return }
        let windowSeconds = Double(dayWindowHours) * 3600
        if let last = displaySnapshots.last {
            scrollAnchor = last.timestamp.addingTimeInterval(-windowSeconds)
        } else {
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: selectedDate)
            comps.hour = 15; comps.minute = 30
            scrollAnchor = cal.date(from: comps)?.addingTimeInterval(-windowSeconds) ?? selectedDate
        }
    }

    private func loadData() {
        let (start, end) = dateRange
        snapshots = (try? DatabaseManager.shared.fetchSnapshots(from: start, to: end)) ?? []
        storedMasterStep = computeMasterStep()
        updateScrollAnchor()
    }

    private func fmt(_ v: Int) -> String {
        NumberFormatter.decimal.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // Y축 레이블용 축약 표시
    // 1억 이상: 정수 억 + 나머지 만 (예: "1억", "1억2500만")
    // 1만 이상: 만 단위 (예: "9800만")
    private func fmtShort(_ v: Int) -> String {
        let absV = Swift.abs(v)
        let sign = v < 0 ? "-" : ""
        if absV >= 100_000_000 {
            let eok = absV / 100_000_000
            let man = (absV % 100_000_000) / 10_000
            return man == 0 ? "\(sign)\(eok)억" : "\(sign)\(eok)억\(man)만"
        }
        if absV >= 10_000 { return "\(sign)\(absV / 10_000)만" }
        return fmt(v)
    }
}
