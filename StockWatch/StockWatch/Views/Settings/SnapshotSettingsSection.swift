import SwiftUI

struct SnapshotSettingsSection: View {
    @State private var marketHoursOnly = SnapshotManager.shared.marketHoursOnly
    @State private var customRanges: [SnapshotTimeRange] = SnapshotManager.shared.customRanges
    @State private var keepDays: Int = SnapshotManager.shared.keepDays
    @State private var newStartTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var newEndTime:   Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var stats: (count: Int, oldest: Date?, newest: Date?) = (0, nil, nil)
    @State private var showDeleteConfirm = false

    var body: some View {
        SettingsFormSection(title: "스냅샷 수집 시간") {
            Toggle("장 시간 (평일 09:00 ~ 15:30)", isOn: $marketHoursOnly)
                .onChange(of: marketHoursOnly) { _, v in SnapshotManager.shared.marketHoursOnly = v }

            if !customRanges.isEmpty {
                ForEach(customRanges) { range in
                    HStack {
                        Text(range.displayString).font(.caption)
                        Spacer()
                        Button {
                            removeRange(range)
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack(spacing: 6) {
                DatePicker("", selection: $newStartTime, displayedComponents: .hourAndMinute)
                    .labelsHidden().frame(width: 85)
                Text("~").foregroundStyle(.secondary)
                DatePicker("", selection: $newEndTime, displayedComponents: .hourAndMinute)
                    .labelsHidden().frame(width: 85)
                Button("추가") { addRange() }
                    .disabled(minutesFrom(newStartTime) >= minutesFrom(newEndTime))
            }
            Text("추가 시간대는 주말 포함 매일 수집됩니다 (프리/애프터 마켓 대응).")
                .font(.caption2).foregroundStyle(.tertiary)
        }

        SettingsFormSection(title: "이력 관리") {
            HStack(spacing: 8) {
                Text("보존 기간").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $keepDays) {
                    Text("30일").tag(30)
                    Text("90일").tag(90)
                    Text("180일").tag(180)
                    Text("365일").tag(365)
                    Text("무제한").tag(-1)
                }
                .labelsHidden()
                .frame(width: 90)
                .onChange(of: keepDays) { _, v in SnapshotManager.shared.keepDays = v }
            }

            HStack(spacing: 8) {
                if stats.count > 0 {
                    Text("\(stats.count)건").font(.caption).foregroundStyle(.secondary)
                    if let oldest = stats.oldest, let newest = stats.newest {
                        Text("(\(oldest.formatted(.dateTime.month().day())) ~ \(newest.formatted(.dateTime.month().day())))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                } else {
                    Text("저장된 스냅샷 없음").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("지금 정리") { cleanup() }
                    .buttonStyle(.borderless).font(.caption)
                    .disabled(keepDays == -1 || stats.count == 0)
                Button("전체 삭제") { showDeleteConfirm = true }
                    .buttonStyle(.borderless).font(.caption)
                    .foregroundStyle(.red)
                    .disabled(stats.count == 0)
            }
        }
        .onAppear { loadStats() }
        .confirmationDialog("스냅샷 전체 삭제", isPresented: $showDeleteConfirm) {
            Button("전체 삭제", role: .destructive) { deleteAll() }
        } message: {
            Text("모든 스냅샷 이력을 삭제합니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }

    private func minutesFrom(_ date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private func addRange() {
        let start = minutesFrom(newStartTime)
        let end   = minutesFrom(newEndTime)
        guard start < end else { return }
        var ranges = SnapshotManager.shared.customRanges
        ranges.append(SnapshotTimeRange(startMinute: start, endMinute: end))
        SnapshotManager.shared.customRanges = ranges
        customRanges = ranges
    }

    private func removeRange(_ range: SnapshotTimeRange) {
        var ranges = SnapshotManager.shared.customRanges
        ranges.removeAll { $0.id == range.id }
        SnapshotManager.shared.customRanges = ranges
        customRanges = ranges
    }

    private func loadStats() {
        stats = (try? DatabaseManager.shared.snapshotStats()) ?? (0, nil, nil)
    }

    private func cleanup() {
        try? DatabaseManager.shared.cleanupSnapshots(keepDays: keepDays)
        loadStats()
    }

    private func deleteAll() {
        try? DatabaseManager.shared.deleteAllSnapshots()
        loadStats()
    }
}
