import XCTest

@MainActor
final class FairNestUITests: XCTestCase {
    func testOnboardingStartsInRealAppFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Share the home load"].waitForExistence(timeout: 5))
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 2))
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.staticTexts["First brain dump"].waitForExistence(timeout: 2))
    }

    func testCreateCardFromBoard() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-uiTestingCompleteOnboarding"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Home Board"].waitForExistence(timeout: 5))
        app.buttons["addCard"].tap()
        let title = app.textFields["cardTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Buy milk")
        app.buttons["saveCard"].tap()

        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3))
    }
}
