import XCTest
@testable import StockWatch

/// SnapshotBackfillManager.findGapDays() 의 공백 탐지 로직을 검증한다.
///
/// 주의: setUp/tearDown에서 portfolio_snapshots 테이블을 초기화한다.
/// 실 데이터 보호를 위해 이 테스트는 개발/CI 환경에서만 실행한다.
@MainActor
final class SnapshotBackfillManagerTests: XCTestCase {

    private var seoulCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    override func setUp() async throws {
        try await super.setUp()
        // 테스트 전 스냅샷 초기화 (공백 탐지가 기존 데이터에 영향받지 않도록)
        try? DatabaseManager.shared.deleteAllSnapshots()
    }

    override func tearDown() async throws {
        try? DatabaseManager.shared.deleteAllSnapshots()
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Seoul 기준 n일 전 자정
    private func dayStart(daysAgo: Int) -> Date {
        let today = seoulCal.startOfDay(for: Date())
        return seoulCal.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    /// Seoul 기준 n일 전 15:30 스냅샷
    private func makeSnapshot(daysAgo: Int) -> PortfolioSnapshot {
        var comps = seoulCal.dateComponents([.year, .month, .day], from: dayStart(daysAgo: daysAgo))
        comps.hour = 15; comps.minute = 30; comps.second = 0
        comps.timeZone = TimeZone(identifier: "Asia/Seoul")
        let ts = seoulCal.date(from: comps)!
        return PortfolioSnapshot(id: nil, timestamp: ts,
                                 totalValue: 1_000_000, totalGain: 0, gainPct: 0.0)
    }

    private func isWeekday(_ date: Date) -> Bool {
        let wd = seoulCal.component(.weekday, from: date)
        return wd != 1 && wd != 7
    }

    // MARK: - Tests

    func test_findGapDays_emptyDB_returnsAllWeekdays() {
        // DB 비어있을 때 lookback 14일 내 모든 평일이 공백으로 반환돼야 함
        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 14)

        let expectedWeekdays = (1...14).map { dayStart(daysAgo: $0) }.filter { isWeekday($0) }
        XCTAssertEqual(Set(gaps), Set(expectedWeekdays),
                       "스냅샷 없는 평일은 모두 공백으로 탐지돼야 함")
    }

    func test_findGapDays_allDaysCovered_returnsEmpty() throws {
        // 7일 전체에 스냅샷 삽입 → 공백 없어야 함
        let snaps = (1...7).map { makeSnapshot(daysAgo: $0) }
        try DatabaseManager.shared.insertSnapshots(snaps)

        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 7)
        XCTAssertTrue(gaps.isEmpty, "모든 날 스냅샷이 있으면 공백이 없어야 함")
    }

    func test_findGapDays_coveredDayNotInGaps() throws {
        // 가장 최근 평일에 스냅샷 삽입 → 그 날은 공백에서 제외돼야 함
        guard let recentWeekdayOffset = (1...7).first(where: { isWeekday(dayStart(daysAgo: $0)) })
        else { return }

        let snap = makeSnapshot(daysAgo: recentWeekdayOffset)
        try DatabaseManager.shared.insertSnapshots([snap])

        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 7)
        let coveredDay = dayStart(daysAgo: recentWeekdayOffset)
        XCTAssertFalse(gaps.contains(coveredDay),
                       "스냅샷이 있는 날은 공백에 포함되지 않아야 함")
    }

    func test_findGapDays_todayNotIncluded() {
        // 오늘은 공백 탐지 범위(< today)에서 제외됨
        let today = seoulCal.startOfDay(for: Date())
        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 7)
        XCTAssertFalse(gaps.contains(today), "오늘은 공백 탐지 범위에서 제외돼야 함")
    }

    func test_findGapDays_weekendsNeverReturned() {
        // 어떤 상태든 주말은 절대 공백으로 반환되지 않아야 함
        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 14)
        for gap in gaps {
            let weekday = seoulCal.component(.weekday, from: gap)
            XCTAssertNotEqual(weekday, 1, "일요일은 공백에 포함되지 않아야 함 — \(gap)")
            XCTAssertNotEqual(weekday, 7, "토요일은 공백에 포함되지 않아야 함 — \(gap)")
        }
    }

    func test_findGapDays_lookback0_returnsEmpty() {
        // lookback 0일 → 범위 없음, 빈 결과
        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 0)
        XCTAssertTrue(gaps.isEmpty, "lookback 0일이면 공백이 없어야 함")
    }

    func test_findGapDays_partialCoverage_returnsOnlyMissingWeekdays() throws {
        // 14일 중 절반만 커버 → 나머지 평일만 공백으로 반환
        let covered = [2, 4, 6, 8, 10, 12, 14]
        let snaps = covered.map { makeSnapshot(daysAgo: $0) }
        try DatabaseManager.shared.insertSnapshots(snaps)

        let gaps = SnapshotBackfillManager.shared.findGapDays(lookbackDays: 14)

        // 커버된 날은 공백에 없어야 함
        for daysAgo in covered {
            let day = dayStart(daysAgo: daysAgo)
            XCTAssertFalse(gaps.contains(day),
                           "\(daysAgo)일 전은 스냅샷이 있으므로 공백이 아니어야 함")
        }

        // 커버되지 않은 평일은 공백에 있어야 함
        let uncovered = (1...14).filter { !covered.contains($0) }
        for daysAgo in uncovered {
            let day = dayStart(daysAgo: daysAgo)
            if isWeekday(day) {
                XCTAssertTrue(gaps.contains(day),
                              "\(daysAgo)일 전 평일은 스냅샷이 없으므로 공백이어야 함")
            }
        }
    }
}
