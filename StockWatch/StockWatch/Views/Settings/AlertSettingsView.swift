import SwiftUI
import AppKit

struct AlertSettingsView: View {
    @State private var conditions: [AlertCondition] = []
    @State private var symbol = ""
    @State private var triggerType: TriggerType = .targetPrice
    @State private var thresholdText = ""
    @State private var disableAfterTrigger = false
    @State private var cooldownMinutes = 60
    @State private var marketHoursOnly: Bool = AlertEvaluator.marketHoursOnly
    @State private var disconnectAlert: Bool = QuoteManager.disconnectAlertEnabled
    @State private var selectedSound: String = NotificationManager.selectedSound

    var body: some View {
        SettingsTabContainer(title: "알림설정") {
            HStack {
                Toggle("장 시간(09:00~15:30)에만 알림 발송", isOn: $marketHoursOnly)
                    .onChange(of: marketHoursOnly) { _, v in AlertEvaluator.marketHoursOnly = v }
                Spacer()
            }
            HStack {
                Toggle("네트워크 단절·복구 시 알림 발송", isOn: $disconnectAlert)
                    .onChange(of: disconnectAlert) { _, v in QuoteManager.disconnectAlertEnabled = v }
                Spacer()
            }
            HStack(spacing: 8) {
                Text("알림 소리")
                    .font(.body)
                Picker("", selection: $selectedSound) {
                    ForEach(NotificationManager.availableSounds, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
                .onChange(of: selectedSound) { _, v in
                    NotificationManager.selectedSound = v
                    if v != "없음" { NSSound(named: v)?.play() }
                }
                Spacer()
            }
            .padding(.bottom, 2)

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
                            ForEach(TriggerType.userConfigurable, id: \.self) {
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
        case .dartDisclosure:
            return "-"
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
