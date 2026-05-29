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

    func testEmptyBoardRoutesToBrainDump() {
        let app = launchCompletedApp()

        XCTAssertTrue(app.staticTexts["No cards yet"].waitForExistence(timeout: 3))
        app.buttons["emptyBrainDump"].tap()

        XCTAssertTrue(app.navigationBars["Brain Dump"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textInput(named: "brainDumpText", timeout: 3).exists)
    }

    func testCardSaveFailureShowsAccessibleErrorAndKeepsEditorOpen() {
        let app = launchCompletedApp(extraLaunchArguments: ["-uiTestingFailCardPersistence"])

        app.buttons["addCard"].tap()
        let title = app.textFields["cardTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Buy milk")
        app.buttons["saveCard"].tap()

        let expectedMessage = "FairNest couldn't save the latest board change. Keep FairNest open and try again before closing the app."
        let saveError = app.descendants(matching: .any).matching(identifier: "cardSaveError").firstMatch
        XCTAssertTrue(saveError.waitForExistence(timeout: 3))
        XCTAssertTrue(saveError.label.contains(expectedMessage), "Actual label: \(saveError.label)")
        XCTAssertTrue(app.textFields["cardTitle"].exists)
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
        XCTAssertEqual(syncSwitch.value as? String, "0")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(syncSwitch.value as? String, "0")
    }

    func testPrivacyExportShowsAccessibleResultMessage() {
        let app = launchCompletedApp()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let privacyLink = app.buttons["Privacy"].firstMatch
        XCTAssertTrue(privacyLink.waitForExistence(timeout: 3))
        privacyLink.tap()

        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 3))
        app.buttons["Export Data"].tap()

        let result = app.descendants(matching: .any).matching(identifier: "privacyResultMessage").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        XCTAssertTrue(result.label.contains("Export file is ready"), "Actual label: \(result.label)")
    }

    func testPrivacyDeleteRequiresTypedConfirmation() {
        let app = launchCompletedApp()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let privacyLink = app.buttons["Privacy"].firstMatch
        XCTAssertTrue(privacyLink.waitForExistence(timeout: 3))
        privacyLink.tap()

        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 3))
        let deleteButton = app.buttons["Delete Local Data"].firstMatch
        if !deleteButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        let confirmationInput = app.textFields["privacyDeletionConfirmationInput"]
        XCTAssertTrue(confirmationInput.waitForExistence(timeout: 3))
        let confirmDelete = app.buttons["privacyDeletionConfirmButton"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 3))
        XCTAssertFalse(confirmDelete.isEnabled)

        confirmationInput.tap()
        confirmationInput.typeText("DELETE LOCAL")
        XCTAssertTrue(confirmDelete.isEnabled)
        app.buttons["Cancel"].tap()
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

    func testCaptureAppStoreScreenshotsWhenDirectoryProvided() throws {
        let screenshotDirectory = try appStoreScreenshotDirectory()
        let emptyApp = launchCompletedApp()
        XCTAssertTrue(emptyApp.staticTexts["No cards yet"].waitForExistence(timeout: 3))
        try captureAppStoreScreenshot("appstore-iphone17promax-empty-light", in: screenshotDirectory)
        emptyApp.terminate()

        let app = launchCompletedApp(extraLaunchArguments: ["-seedDemoData"])
        XCTAssertTrue(app.staticTexts["Set out recycling"].waitForExistence(timeout: 3))
        try captureAppStoreScreenshot("appstore-iphone17promax-board-light", in: screenshotDirectory)

        app.tabBars.buttons["Brain Dump"].tap()
        let brainDumpEditor = app.textInput(named: "brainDumpText", timeout: 3)
        XCTAssertTrue(brainDumpEditor.exists)
        brainDumpEditor.tap()
        brainDumpEditor.typeText("meal plan")
        app.buttons["dismissBrainDumpKeyboard"].tap()
        app.buttons["Suggest Cards"].tap()
        XCTAssertTrue(app.textFields["brainDumpSuggestionTitle"].waitForExistence(timeout: 10))
        try captureAppStoreScreenshot("appstore-iphone17promax-brain-dump-light", in: screenshotDirectory)

        app.tabBars.buttons["Check-In"].tap()
        let heavy = app.textViews["checkInFeltHeavy"]
        XCTAssertTrue(heavy.waitForExistence(timeout: 3))
        heavy.tap()
        heavy.typeText("Meal planning")
        app.buttons["checkInNext"].tap()

        let done = app.textViews["checkInGotDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        done.typeText("Laundry and groceries")
        app.buttons["checkInNext"].tap()

        let ownership = app.textViews["checkInNeedsOwnership"]
        XCTAssertTrue(ownership.waitForExistence(timeout: 3))
        ownership.tap()
        ownership.typeText("partner owns trash night")
        app.buttons["checkInNext"].tap()

        let appreciation = app.textViews["checkInAppreciation"]
        XCTAssertTrue(appreciation.waitForExistence(timeout: 3))
        appreciation.tap()
        appreciation.typeText("Thanks for making dinner")
        app.buttons["checkInNext"].tap()

        XCTAssertTrue(app.textFields["checkInOwnershipTitle"].waitForExistence(timeout: 3))
        try captureAppStoreScreenshot("appstore-iphone17promax-check-in-light", in: screenshotDirectory)

        app.tabBars.buttons["Pair"].tap()
        XCTAssertTrue(app.navigationBars["Pair"].waitForExistence(timeout: 3))
        try captureAppStoreScreenshot("appstore-iphone17promax-pairing-light", in: screenshotDirectory)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try captureAppStoreScreenshot("appstore-iphone17promax-settings-light", in: screenshotDirectory)
    }

    private func launchCompletedApp(extraLaunchArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetFairNest", "-uiTestingCompleteOnboarding", "-useRuleBasedParser"] + extraLaunchArguments
        app.launch()
        if !app.navigationBars["Home Board"].waitForExistence(timeout: 5) {
            completeOnboardingIfNeeded(in: app)
        }
        XCTAssertTrue(app.navigationBars["Home Board"].waitForExistence(timeout: 8))
        return app
    }

    private func completeOnboardingIfNeeded(in app: XCUIApplication) {
        let timeout = Date().addingTimeInterval(8)
        while Date() < timeout {
            if app.navigationBars["Home Board"].exists {
                return
            }
            let startButton = app.buttons["Start FairNest"]
            if startButton.waitForExistence(timeout: 1) {
                startButton.tap()
                continue
            }
            let continueButton = app.buttons["onboardingContinue"]
            if continueButton.waitForExistence(timeout: 1) {
                continueButton.tap()
                continue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func appStoreScreenshotDirectory() throws -> URL {
        if let directory = ProcessInfo.processInfo.environment["FAIRNEST_APP_STORE_SCREENSHOT_DIR"],
           !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sentinel = repoRoot.appendingPathComponent("QA/.capture-app-store-screenshots")
        guard FileManager.default.fileExists(atPath: sentinel.path) else {
            throw XCTSkip("Create QA/.capture-app-store-screenshots to write App Store screenshots.")
        }

        let screenshots = repoRoot.appendingPathComponent("QA/Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        return screenshots
    }

    private func captureAppStoreScreenshot(
        _ name: String,
        in directory: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = directory.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: url, options: .atomic)
        } catch {
            XCTFail("Failed to write \(url.path): \(error)", file: file, line: line)
            throw error
        }
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
