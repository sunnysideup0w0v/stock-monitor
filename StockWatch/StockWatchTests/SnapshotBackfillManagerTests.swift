import XCTest
@testable import StockWatch

/// SnapshotBackfillManager.findGapDays() 의 공백 탐지 로직을 검증한다.
///
/// 실제 스냅샷 데이터를 보호하기 위해 테스트 전용 타임스탬프만 삽입하고
/// tearDown에서 해당 범위만 정밀 삭제한다. deleteAllSnapshots()는 사용하지 않는다.
@MainActor
final class SnapshotBackfillManagerTests: XCTestCase {

    private var seoulCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    /// 테스트에서 삽입한 스냅샷의 타임스탬프 범위 (tearDown 정리용)
    private var insertedRange: (from: Date, to: Date)?

    override func setUp() async throws {
        try await super.setUp()
        insertedRange = nil
    }

    override func tearDown() async throws {
        // 이번 테스트에서 삽입한 타임스탬프 범위만 삭제
        if let r = insertedRange {
            try? DatabaseManager.shared.deleteSnapshots(from: r.from, to: r.to)
        }
        insertedRange = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Seoul 기준 n일 전 자정
    private func dayStart(daysAgo: Int) -> Date {
        let today = seoulCal.startOfDay(for: Date())
        return seoulCal.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    /// Seoul 기준 n일 전 15:30 타임스탬프 스냅샷
    private func makeSnapshot(daysAgo: Int) -> PortfolioSnapshot {
        var comps = seoulCal.dateComponents([.year, .month, .day], from: dayStart(daysAgo: daysAgo))
        comps.hour = 15; comps.minute = 30; comps.second = 0
        comps.timeZone = TimeZone(identifier: "Asia/Seoul")
        let ts = seoulCal.date(from: comps)!
        return PortfolioSnapshot(id: nil, timestamp: ts,
                                 totalValue: 1_000_000, totalGain: 0, gainPct: 0.0)
    }

    /// 스냅샷 삽입 + tearDown 정리 범위 등록
    private func insert(daysAgo values: [Int]) throws {
        let snaps = values.map { makeSnapshot(daysAgo: $0) }
        try DatabaseManager.shared.insertSnapshots(snaps)
        // 삽입 범위 기록
        let from = dayStart(daysAgo: values.max()!)
            .addingTimeInterval(-1)
        let to = dayStart(daysAgo: values.min()!)
            .addingTimeInterval(86400)
        insertedRange = (from: from, to: to)
    }

    private func isWeekday(_ date: Date) -> Bool {
        let wd = seoulCal.component(.weekday, from: date)
        return wd != 1 && wd != 7
    }

    // MARK: - Tests

    func test_findGapDays_todayNotIncluded() {
        let today = seoulCal.startOfDay(for: Date())
        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 7)
        XCTAssertFalse(gaps.contains(today), "오늘은 공백 탐지 범위에서 제외돼야 함")
    }

    func test_findGapDays_lookback0_returnsEmpty() {
        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 0)
        XCTAssertTrue(gaps.isEmpty, "lookback 0일이면 공백이 없어야 함")
    }

    func test_findGapDays_allGapsAreWeekdays() {
        // DB 상태와 무관하게 반환된 공백은 모두 평일이어야 함
        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 14)
        for gap in gaps {
            let wd = seoulCal.component(.weekday, from: gap)
            XCTAssertNotEqual(wd, 1, "일요일은 공백에 포함되지 않아야 함")
            XCTAssertNotEqual(wd, 7, "토요일은 공백에 포함되지 않아야 함")
        }
    }

    func test_findGapDays_coveredDayNotInGaps() throws {
        // 가장 최근 평일에 스냅샷 삽입 → 그 날은 공백에서 제외돼야 함
        guard let recentOffset = (1...7).first(where: { isWeekday(dayStart(daysAgo: $0)) })
        else { XCTFail("최근 7일 내 평일이 없음 (달력 오류)"); return }

        try insert(daysAgo: [recentOffset])

        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 7)
        let coveredDay = dayStart(daysAgo: recentOffset)
        XCTAssertFalse(gaps.contains(coveredDay),
                       "스냅샷이 있는 날은 공백에 포함되지 않아야 함")
    }

    func test_findGapDays_insertedDayReducesGapCount() throws {
        // 스냅샷 삽입 전후 공백 수 비교 — 커버된 날이 평일이면 1개 감소해야 함
        guard let recentOffset = (1...7).first(where: { isWeekday(dayStart(daysAgo: $0)) })
        else { XCTFail("최근 7일 내 평일이 없음"); return }

        let before = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 7)
        let day = dayStart(daysAgo: recentOffset)

        // 해당 날이 아직 공백인 경우에만 테스트 의미 있음
        guard before.contains(day) else { return }

        try insert(daysAgo: [recentOffset])
        let after = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 7)
        XCTAssertEqual(after.count, before.count - 1,
                       "스냅샷 1개 추가 후 공백은 1개 줄어야 함")
    }

    func test_findGapDays_multipleCoveredDays_allExcluded() throws {
        // 3개 평일 커버 → 모두 공백에서 제외
        let weekdays = (1...14).filter { isWeekday(dayStart(daysAgo: $0)) }.prefix(3)
        guard weekdays.count == 3 else { return }

        let offsets = Array(weekdays)
        try insert(daysAgo: offsets)

        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 14)
        for offset in offsets {
            let day = dayStart(daysAgo: offset)
            XCTAssertFalse(gaps.contains(day),
                           "\(offset)일 전 평일은 스냅샷이 있으므로 공백이 아니어야 함")
        }
    }

    func test_findGapDays_returnsChronologicalOrder() {
        // 반환 순서: 오래된 날부터 최근 날 순서 (while 루프가 start→today 방향)
        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 14)
        guard gaps.count > 1 else { return }
        for i in 1..<gaps.count {
            XCTAssertLessThan(gaps[i - 1], gaps[i], "공백 목록은 날짜 오름차순이어야 함")
        }
    }
}
