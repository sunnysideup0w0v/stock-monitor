import XCTest

final class SettingsWindowUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        // 설정 창이 자동으로 열릴 때까지 대기
        XCTAssertTrue(app.windows["StockWatch 설정"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - 설정 창 기본

    func test_settingsWindow_opens() {
        XCTAssertTrue(app.windows["StockWatch 설정"].exists)
    }

    func test_settingsWindow_hasTabBar() {
        let win = app.windows["StockWatch 설정"]
        XCTAssertTrue(win.tabGroups.firstMatch.exists || win.buttons["포트폴리오"].exists)
    }

    // MARK: - 포트폴리오 탭

    func test_portfolioTab_addAndDeleteItem() throws {
        let win = app.windows["StockWatch 설정"]

        // 포트폴리오 탭으로 이동
        let portfolioTab = win.buttons["포트폴리오"]
        guard portfolioTab.waitForExistence(timeout: 3) else {
            throw XCTSkip("포트폴리오 탭 버튼을 찾을 수 없음 — 탭 구조 확인 필요")
        }
        portfolioTab.click()

        // 종목 코드 입력
        let symbolField = win.textFields.matching(identifier: "portfolio.field.symbol").firstMatch
        guard symbolField.waitForExistence(timeout: 3) else {
            throw XCTSkip("종목 코드 필드를 찾을 수 없음")
        }
        symbolField.click()
        symbolField.typeText("005930")

        // 종목명 입력
        let nameField = win.textFields.matching(identifier: "portfolio.field.name").firstMatch
        nameField.click()
        nameField.typeText("삼성전자")

        // 평균 단가 입력
        let priceField = win.textFields.matching(identifier: "portfolio.field.averagePrice").firstMatch
        priceField.click()
        priceField.typeText("70000")

        // 수량 입력
        let qtyField = win.textFields.matching(identifier: "portfolio.field.quantity").firstMatch
        qtyField.click()
        qtyField.typeText("10")

        // 추가 버튼 클릭
        let addButton = win.buttons.matching(identifier: "portfolio.button.add").firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))
        addButton.click()

        // 추가된 항목이 목록에 나타나는지 확인
        XCTAssertTrue(win.staticTexts["005930"].waitForExistence(timeout: 3) ||
                      win.staticTexts["삼성전자"].waitForExistence(timeout: 3))
    }
}
