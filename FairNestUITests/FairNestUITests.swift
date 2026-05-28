import XCTest

@MainActor
final class FairNestUITests: XCTestCase {
    func testOnboardingStartsInRealAppFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-useRuleBasedParser"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Share the home load"].waitForExistence(timeout: 5))
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 2))
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.staticTexts["First brain dump"].waitForExistence(timeout: 2))
    }

    func testOnboardingBrainDumpCreatesStarterCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-useRuleBasedParser"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Share the home load"].waitForExistence(timeout: 5))
        app.buttons["onboardingContinue"].tap()
        app.buttons["onboardingContinue"].tap()

        let editor = app.textViews["onboardingBrainDump"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("buy milk")
        app.buttons["dismissOnboardingBrainDumpKeyboard"].tap()
        app.buttons["onboardingContinue"].tap()

        XCTAssertTrue(app.textFields["brainDumpSuggestionTitle"].waitForExistence(timeout: 10))
        app.buttons["onboardingContinue"].tap()

        XCTAssertTrue(app.navigationBars["Home Board"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Buy Milk"].waitForExistence(timeout: 3))
    }

    func testCreateCardFromBoard() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-uiTestingCompleteOnboarding", "-useRuleBasedParser"]
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

    func testStandaloneBrainDumpSavesReviewedCardToBoard() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-uiTestingCompleteOnboarding", "-useRuleBasedParser"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Home Board"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Brain Dump"].tap()

        let editor = app.textViews["brainDumpText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("buy milk")
        app.buttons["dismissBrainDumpKeyboard"].tap()
        app.buttons["Suggest Cards"].tap()

        XCTAssertTrue(app.textFields["brainDumpSuggestionTitle"].waitForExistence(timeout: 10))
        app.buttons["saveBrainDumpSuggestions"].tap()

        app.tabBars.buttons["Board"].tap()
        XCTAssertTrue(app.staticTexts["Buy Milk"].waitForExistence(timeout: 3))
    }

    func testSettingsShowsPrivacySyncAndReminderControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-uiTestingCompleteOnboarding", "-useRuleBasedParser"]
        app.launch()

        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy"].exists)
        XCTAssertTrue(app.switches["Use iCloud Sync"].exists)
        XCTAssertTrue(app.staticTexts["Notifications"].exists)
    }

    func testSettingsRequiresConfirmationBeforeTurningOnICloudSync() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-uiTestingCompleteOnboarding", "-useRuleBasedParser"]
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.switches["Use iCloud Sync"].tap()

        XCTAssertTrue(app.buttons["Turn On iCloud Sync"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Existing local cards will sync to iCloud. If this device joins a shared household, cards can be visible to invited participants. Weekly check-ins stay local."].exists)
        app.buttons["Cancel"].tap()
    }

    func testWeeklyCheckInSavesReviewedOwnershipChange() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-uiTestingCompleteOnboarding", "-useRuleBasedParser"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Home Board"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Check-In"].tap()

        let heavy = app.textViews["checkInFeltHeavy"]
        XCTAssertTrue(heavy.waitForExistence(timeout: 3))
        heavy.tap()
        heavy.typeText("Meal planning")
        app.buttons["checkInNext"].tap()

        let done = app.textViews["checkInGotDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        done.typeText("Laundry")
        app.buttons["checkInNext"].tap()

        let ownership = app.textViews["checkInNeedsOwnership"]
        XCTAssertTrue(ownership.waitForExistence(timeout: 3))
        ownership.tap()
        ownership.typeText("partner owns trash")
        app.buttons["checkInNext"].tap()

        let appreciation = app.textViews["checkInAppreciation"]
        XCTAssertTrue(appreciation.waitForExistence(timeout: 3))
        appreciation.tap()
        appreciation.typeText("Thanks for dinner")
        app.buttons["checkInNext"].tap()

        XCTAssertTrue(app.textFields["checkInOwnershipTitle"].waitForExistence(timeout: 3))
        app.buttons["checkInNext"].tap()

        XCTAssertTrue(app.staticTexts["Check-in saved"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Board"].tap()
        XCTAssertTrue(app.staticTexts["Trash"].waitForExistence(timeout: 3))
    }
}
