import SwiftUI
import AppKit

struct AlertHistoryView: View {
    @State private var history: [AlertHistory] = []
    @State private var symbolNames: [String: String] = [:]
    @State private var symbolFilter = ""
    @State private var typeFilter: TriggerType? = nil
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()

    private var filtered: [AlertHistory] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        let end   = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
        return history.filter { item in
            let dateOK   = item.triggeredAt >= start && item.triggeredAt <= end
            let nameOK   = symbolFilter.isEmpty
                        || item.symbol.localizedCaseInsensitiveContains(symbolFilter)
                        || (symbolNames[item.symbol] ?? "").localizedCaseInsensitiveContains(symbolFilter)
            let typeOK   = typeFilter == nil || item.triggerType == typeFilter
            return dateOK && nameOK && typeOK
        }
    }

    var body: some View {
        SettingsTabContainer(title: "알림 이력") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("기간").font(.caption).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                    DatePicker("", selection: $startDate, displayedComponents: .date).labelsHidden()
                    Text("~").foregroundStyle(.secondary)
                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date).labelsHidden()
                    Spacer()
                    ForEach(["오늘", "1주", "1달", "전체"], id: \.self) { preset in
                        Button(preset) { applyPreset(preset) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }

                HStack(spacing: 6) {
                    Text("유형").font(.caption).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                    Picker("", selection: $typeFilter) {
                        Text("전체").tag(Optional<TriggerType>.none)
                        ForEach(TriggerType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(Optional(type))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    Text("종목").font(.caption).foregroundStyle(.secondary)
                    TextField("검색", text: $symbolFilter).frame(width: 80)
                    Spacer()
                    Text("\(filtered.count)건").font(.caption).foregroundStyle(.tertiary)
                    Button("내보내기") { exportCSV() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    Button("전체 삭제") { hideAll() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(filtered.isEmpty ? Color.secondary : Color.red)
                        .disabled(filtered.isEmpty)
                    Button("새로고침") { load() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            if filtered.isEmpty {
                Text("이력이 없습니다")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered, id: \.id) { item in
                        AlertHistoryRowView(item: item, symbolName: symbolNames[item.symbol])
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    hide(item: item)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.bordered)
            }
        }
        .onAppear { load() }
    }

    private func applyPreset(_ preset: String) {
        let now = Date()
        endDate = now
        switch preset {
        case "오늘": startDate = Calendar.current.startOfDay(for: now)
        case "1주":  startDate = Calendar.current.date(byAdding: .day,   value: -7,  to: now) ?? now
        case "1달":  startDate = Calendar.current.date(byAdding: .month, value: -1,  to: now) ?? now
        case "전체": startDate = Date(timeIntervalSince1970: 0)
        default: break
        }
    }

    private func hide(item: AlertHistory) {
        guard let id = item.id else { return }
        try? DatabaseManager.shared.hideAlertHistory(id: id)
        history.removeAll { $0.id == id }
    }

    private func hideAll() {
        try? DatabaseManager.shared.hideAllAlertHistory()
        history.removeAll()
    }

    private func load() {
        history = (try? DatabaseManager.shared.fetchAlertHistory(limit: 500)) ?? []

        var names: [String: String] = [:]
        let watchlist = (try? DatabaseManager.shared.fetchWatchlist()) ?? []
        let portfolio = (try? DatabaseManager.shared.fetchPortfolio()) ?? []
        for item in portfolio { names[item.symbol] = item.name }
        for item in watchlist { names[item.symbol] = item.alias ?? item.name }
        symbolNames = names
    }

    private func exportCSV() {
        let header = "날짜,시간,종목코드,종목명,알림유형,내용\n"
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH:mm:ss"

        let rows = filtered.map { item -> String in
            let date  = dateFmt.string(from: item.triggeredAt)
            let time  = timeFmt.string(from: item.triggeredAt)
            let name  = item.symbol == "PORTFOLIO" ? "전체 포트폴리오" : (symbolNames[item.symbol] ?? "")
            let msg   = item.message.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(date)\",\"\(time)\",\"\(item.symbol)\",\"\(name)\",\"\(item.triggerType.displayName)\",\"\(msg)\""
        }.joined(separator: "\n")

        let csvString = header + rows

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "alert_history_\(dateFmt.string(from: Date())).csv"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var data = Data([0xEF, 0xBB, 0xBF])
            if let body = csvString.data(using: .utf8) { data.append(body) }
            try? data.write(to: url)
        }
    }
}

struct AlertHistoryRowView: View {
    let item: AlertHistory
    let symbolName: String?

    private var displaySymbol: String {
        if item.symbol == "PORTFOLIO" { return item.stockName ?? "전체 포트폴리오" }
        let name = item.stockName ?? symbolName
        if let name { return "\(name)(\(item.symbol))" }
        return item.symbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(displaySymbol)
                    .font(.body).fontWeight(.medium)
                Text(item.triggerType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(item.triggeredAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(item.triggeredAt.formatted(.dateTime.month().day()))
                    .font(.caption2).foregroundStyle(.tertiary)
                if item.triggerType == .dartDisclosure, let rceptNo = item.metadata {
                    Button("공시 보기") {
                        let urlStr = "https://dart.fss.or.kr/dsaf001/main.do?rcpNo=\(rceptNo)"
                        if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
            Text(item.message)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}
