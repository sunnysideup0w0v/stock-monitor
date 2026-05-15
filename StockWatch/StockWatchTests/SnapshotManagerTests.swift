import XCTest
@testable import StockWatch

final class SnapshotManagerTests: XCTestCase {

    private var savedMarketHoursOnly = true
    private var savedRanges: [SnapshotTimeRange] = []

    override func setUp() async throws {
        try await super.setUp()
        let values = await MainActor.run {
            (SnapshotManager.shared.marketHoursOnly, SnapshotManager.shared.customRanges)
        }
        savedMarketHoursOnly = values.0
        savedRanges = values.1
    }

    override func tearDown() async throws {
        let mho = savedMarketHoursOnly
        let cr  = savedRanges
        await MainActor.run {
            SnapshotManager.shared.marketHoursOnly = mho
            SnapshotManager.shared.customRanges    = cr
        }
        try await super.tearDown()
    }

    // MARK: - marketHoursOnly=true

    @MainActor func test_marketHours_weekday_0900_active() {
        configure(marketHoursOnly: true, ranges: [])
        XCTAssertTrue(SnapshotManager.shared.isActiveTime(weekday: 2, current: 9 * 60))
    }

    @MainActor func test_marketHours_weekday_1530_active() {
        configure(marketHoursOnly: true, ranges: [])
        XCTAssertTrue(SnapshotManager.shared.isActiveTime(weekday: 2, current: 15 * 60 + 30))
    }

    @MainActor func test_marketHours_weekday_1531_inactive() {
        configure(marketHoursOnly: true, ranges: [])
        XCTAssertFalse(SnapshotManager.shared.isActiveTime(weekday: 2, current: 15 * 60 + 31))
    }

    @MainActor func test_marketHours_weekday_0859_inactive() {
        configure(marketHoursOnly: true, ranges: [])
        XCTAssertFalse(SnapshotManager.shared.isActiveTime(weekday: 2, current: 8 * 60 + 59))
    }

    @MainActor func test_marketHours_saturday_inactive() {
        configure(marketHoursOnly: true, ranges: [])
        XCTAssertFalse(SnapshotManager.shared.isActiveTime(weekday: 7, current: 10 * 60))
    }

    @MainActor func test_marketHours_sunday_inactive() {
        configure(marketHoursOnly: true, ranges: [])
        XCTAssertFalse(SnapshotManager.shared.isActiveTime(weekday: 1, current: 10 * 60))
    }

    // MARK: - customRanges

    @MainActor func test_customRange_withinRange_active() {
        let range = SnapshotTimeRange(startMinute: 8 * 60, endMinute: 9 * 60)
        configure(marketHoursOnly: false, ranges: [range])
        XCTAssertTrue(SnapshotManager.shared.isActiveTime(weekday: 7, current: 8 * 60 + 30))
    }

    @MainActor func test_customRange_outsideRange_inactive() {
        let range = SnapshotTimeRange(startMinute: 8 * 60, endMinute: 9 * 60)
        configure(marketHoursOnly: false, ranges: [range])
        XCTAssertFalse(SnapshotManager.shared.isActiveTime(weekday: 2, current: 7 * 60))
    }

    @MainActor func test_noRules_inactive() {
        configure(marketHoursOnly: false, ranges: [])
        XCTAssertFalse(SnapshotManager.shared.isActiveTime(weekday: 2, current: 10 * 60))
    }

    // MARK: - Helpers

    @MainActor private func configure(marketHoursOnly: Bool, ranges: [SnapshotTimeRange]) {
        SnapshotManager.shared.marketHoursOnly = marketHoursOnly
        SnapshotManager.shared.customRanges    = ranges
    }
}
