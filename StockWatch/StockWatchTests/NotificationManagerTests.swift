import XCTest
@testable import StockWatch

final class NotificationManagerTests: XCTestCase {

    private let udKey = "Notification.sound"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: udKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: udKey)
        try await super.tearDown()
    }

    // MARK: - selectedSound

    func test_selectedSound_defaultIsGlass() {
        UserDefaults.standard.removeObject(forKey: udKey)
        XCTAssertEqual(NotificationManager.selectedSound, "Glass")
    }

    func test_selectedSound_persistsToUserDefaults() {
        NotificationManager.selectedSound = "Ping"
        XCTAssertEqual(NotificationManager.selectedSound, "Ping")
        XCTAssertEqual(UserDefaults.standard.string(forKey: udKey), "Ping")
    }

    func test_selectedSound_noneOption_isInList() {
        XCTAssertTrue(NotificationManager.availableSounds.contains("없음"))
    }

    // MARK: - availableSounds

    func test_availableSounds_hasExpectedCount() {
        // 14종 시스템 사운드 + "없음" = 15개
        XCTAssertEqual(NotificationManager.availableSounds.count, 15)
    }

    func test_availableSounds_noneIsFirst() {
        XCTAssertEqual(NotificationManager.availableSounds.first, "없음")
    }
}
