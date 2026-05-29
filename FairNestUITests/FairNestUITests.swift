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

        let editor = app.textInput(named: "onboardingBrainDump", timeout: 3)
        XCTAssertTrue(editor.exists)
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
        let app = launchCompletedApp()

        app.buttons["addCard"].tap()
        let title = app.textFields["cardTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Buy milk")
        app.buttons["saveCard"].tap()

        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3))
    }

    func testStandaloneBrainDumpSavesReviewedCardToBoard() {
        let app = launchCompletedApp()

        app.tabBars.buttons["Brain Dump"].tap()

        let editor = app.textInput(named: "brainDumpText", timeout: 3)
        XCTAssertTrue(editor.exists)
        editor.tap()
        editor.typeText("buy milk")
        app.buttons["dismissBrainDumpKeyboard"].tap()
        app.buttons["Suggest Cards"].tap()

        XCTAssertTrue(app.textFields["brainDumpSuggestionTitle"].waitForExistence(timeout: 10))
        app.buttons["saveBrainDumpSuggestions"].tap()

        XCTAssertTrue(app.staticTexts["Saved 1 card."].waitForExistence(timeout: 3))
        app.tabBars.buttons["Board"].tap()
        XCTAssertTrue(app.staticTexts["Buy Milk"].waitForExistence(timeout: 3))
    }

    func testBrainDumpReviewUsesDistinctAccessibilityLabels() {
        let app = launchCompletedApp()

        app.tabBars.buttons["Brain Dump"].tap()

        let editor = app.textInput(named: "brainDumpText", timeout: 3)
        XCTAssertTrue(editor.exists)
        editor.tap()
        editor.typeText("buy milk. laundry every Sunday")
        app.buttons["dismissBrainDumpKeyboard"].tap()
        app.buttons["Suggest Cards"].tap()

        let firstTitle = app.textFields.matching(
            NSPredicate(format: "label == %@", "Title for suggestion 1")
        ).firstMatch
        let secondTitle = app.textFields.matching(
            NSPredicate(format: "label == %@", "Title for suggestion 2")
        ).firstMatch
        let firstToggle = app.switches.matching(
            NSPredicate(format: "label == %@", "Include suggestion 1: Buy Milk")
        ).firstMatch

        XCTAssertTrue(firstTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(firstToggle.exists)

        if !secondTitle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 3))
    }

    func testSettingsShowsPrivacySyncAndReminderControls() {
        let app = launchCompletedApp()

        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy"].exists)
        XCTAssertTrue(app.switches["settingsICloudSync"].exists)
        XCTAssertTrue(app.staticTexts["Notifications"].exists)
    }

    func testSettingsRequiresConfirmationBeforeTurningOnICloudSync() {
        let app = launchCompletedApp()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let syncSwitch = app.switches["settingsICloudSync"]
        XCTAssertTrue(syncSwitch.waitForExistence(timeout: 3))
        syncSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["Turn on iCloud Sync?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Turn On iCloud Sync"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(syncSwitch.value as? String, "0")
    }

    func testWeeklyCheckInSavesReviewedOwnershipChange() {
        let app = launchCompletedApp()

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

    func testWeeklyCheckInConfirmsBeforeSavingEmptyReflection() {
        let app = launchCompletedApp()

        app.tabBars.buttons["Check-In"].tap()

        let nextButton = app.buttons["checkInNext"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
        nextButton.tap()
        nextButton.tap()
        nextButton.tap()
        nextButton.tap()

        XCTAssertTrue(app.staticTexts["Empty check-in"].waitForExistence(timeout: 3))
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["Save Empty Check-In?"].waitForExistence(timeout: 3))
        app.buttons["Keep Editing"].tap()
        XCTAssertFalse(app.staticTexts["Check-in saved"].exists)

        nextButton.tap()
        app.buttons["Save Empty Check-In"].tap()
        XCTAssertTrue(app.staticTexts["Check-in saved"].waitForExistence(timeout: 3))
    }

    private func launchCompletedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-uiTestingCompleteOnboarding", "-useRuleBasedParser"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home Board"].waitForExistence(timeout: 8))
        return app
    }
}

private extension XCUIApplication {
    func textInput(named identifier: String, timeout: TimeInterval) -> XCUIElement {
        let textField = textFields[identifier]
        if textField.waitForExistence(timeout: timeout) {
            return textField
        }

        let textView = textViews[identifier]
        _ = textView.waitForExistence(timeout: 1)
        return textView
    }
}
