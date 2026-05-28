import XCTest
import UserNotifications
@testable import FairNest

@MainActor
final class ReminderAndCheckInTests: XCTestCase {
    func testReminderFactoryBuildsDueTaskRequest() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let card = LoadCard(title: "Set out trash", type: .recurringResponsibility, dueDate: due)

        let request = ReminderRequestFactory.dueTaskRequest(for: card)

        XCTAssertEqual(request?.title, "Shared responsibility")
        XCTAssertEqual(request?.body, "Open FairNest to review this item.")
        XCTAssertFalse(request?.body.contains("Set out trash") ?? true)
        XCTAssertEqual(request?.repeats, false)
    }

    func testWeeklyCheckInOutputsAtMostThreeOwnershipChanges() {
        let draft = WeeklyCheckInDraft(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "partner owns trash. we handle meal plan. I handle school forms. extra item",
            appreciation: "Thanks for dinner"
        )

        let changes = WeeklyCheckInEngine.generateChanges(from: draft, cards: [])

        XCTAssertLessThanOrEqual(changes.count, 3)
        XCTAssertTrue(changes.contains { $0.owner == .partner })
    }

    func testWeeklyCheckInDropsEmptyOwnershipPhrasesAndCleansTitles() {
        let draft = WeeklyCheckInDraft(
            feltHeavy: "",
            gotDone: "",
            needsOwnership: "we will. partner owns trash. we handle meal plan. I handle school forms",
            appreciation: ""
        )

        let changes = WeeklyCheckInEngine.generateChanges(from: draft, cards: [])

        XCTAssertEqual(changes.map(\.title), ["Trash", "Meal Plan", "School Forms"])
        XCTAssertEqual(changes.map(\.owner), [.partner, .shared, .me])
    }

    func testWeeklyCheckInDoesNotInventOwnershipWhenOwnershipFieldIsBlank() {
        let draft = WeeklyCheckInDraft(
            feltHeavy: "Planning felt heavy",
            gotDone: "Laundry",
            needsOwnership: "",
            appreciation: "Thanks"
        )
        let sharedCard = LoadCard(title: "Grocery plan", owner: .shared, effort: .heavy)

        let changes = WeeklyCheckInEngine.generateChanges(from: draft, cards: [sharedCard])

        XCTAssertTrue(changes.isEmpty)
    }

    func testWeeklyCheckInAppliesReviewedChangesByExactTitleOnly() {
        let rent = LoadCard(title: "Rent", owner: .me)
        let currentBudget = LoadCard(title: "Current budget", owner: .shared)
        let changes = [
            OwnershipChange(title: "Rent", owner: .partner, reason: "Reviewed")
        ]

        let updated = WeeklyCheckInEngine.cardsAfterApplying(changes, to: [currentBudget, rent])

        XCTAssertEqual(updated.first { $0.title == "Rent" }?.owner, .partner)
        XCTAssertEqual(updated.first { $0.title == "Current budget" }?.owner, .shared)
    }

    func testAppServicesSchedulesAndCancelsDueCardReminders() async {
        let reminderScheduler = CapturingReminderScheduler()
        let services = AppServices(
            cardStore: LocalCardStore(fileURL: tempURL()),
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            reminderScheduler: reminderScheduler
        )
        let dueCard = LoadCard(title: "Pay rent", status: .planned, dueDate: Date(timeIntervalSinceNow: 3600))
        let doneCard = LoadCard(title: "Done", status: .done, dueDate: Date(timeIntervalSinceNow: 3600))

        await services.handleCardsChanged([dueCard, doneCard])

        XCTAssertEqual(reminderScheduler.scheduledCardIDs, [dueCard.id])
        XCTAssertEqual(reminderScheduler.cancelledCardIDs, [doneCard.id])
    }

    func testSchedulingCurrentCardsCatchesCardsCreatedBeforeNotificationPermission() async throws {
        let reminderScheduler = CapturingReminderScheduler()
        let cardStore = LocalCardStore(fileURL: tempURL())
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            reminderScheduler: reminderScheduler
        )
        let dueCard = LoadCard(title: "Pay rent", status: .planned, dueDate: Date(timeIntervalSinceNow: 3600))
        cardStore.upsert(dueCard)
        reminderScheduler.scheduledCardIDs = []

        try await services.scheduleRemindersForCurrentCards()

        XCTAssertEqual(reminderScheduler.scheduledCardIDs, [dueCard.id])
    }

    func testSchedulingCurrentCardsSurfacesDueReminderFailures() async throws {
        let reminderScheduler = CapturingReminderScheduler()
        reminderScheduler.scheduleDueTaskError = TestReminderError.schedulingFailed
        let cardStore = LocalCardStore(fileURL: tempURL())
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            reminderScheduler: reminderScheduler
        )
        cardStore.upsert(LoadCard(title: "Private task", status: .planned, dueDate: Date(timeIntervalSinceNow: 3600)))

        do {
            try await services.scheduleRemindersForCurrentCards()
            XCTFail("Expected reminder scheduling to surface the scheduler error.")
        } catch {
            XCTAssertEqual(error.localizedDescription, TestReminderError.schedulingFailed.localizedDescription)
        }
        XCTAssertEqual(services.lastReminderMessage, TestReminderError.schedulingFailed.localizedDescription)
    }

    func testSchedulingCurrentCardsCancelsOrphanedDueReminder() async throws {
        let reminderScheduler = CapturingReminderScheduler()
        let orphanedCardID = UUID()
        reminderScheduler.pendingIdentifiers = [
            ReminderRequestFactory.cardReminderIdentifier(for: orphanedCardID)
        ]
        let services = AppServices(
            cardStore: LocalCardStore(fileURL: tempURL()),
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            reminderScheduler: reminderScheduler
        )

        try await services.scheduleRemindersForCurrentCards()

        XCTAssertEqual(reminderScheduler.cancelledCardIDs, [orphanedCardID])
    }

    func testPrivacyDeleteClearsDataDisablesSyncAndCancelsReminders() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
        }
        let reminderScheduler = CapturingReminderScheduler()
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        _ = cardStore.add(BrainDumpSuggestion(title: "Private task", type: .task))
        try checkInStore.save(CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: []
        ))
        let exportURL = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportToTemporaryFile()
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: checkInStore,
            reminderScheduler: reminderScheduler
        )
        services.iCloudSyncEnabled = true

        try await services.deleteAllLocalDataForPrivacy()

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertTrue(checkInStore.records.isEmpty)
        XCTAssertTrue(reminderScheduler.cancelledAllFairNestReminders)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
    }

    func testPrivacyDeleteFailureDoesNotCancelRemindersOrRemoveTemporaryExport() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
        }
        let reminderScheduler = CapturingReminderScheduler()
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInURL = tempURL()
        let checkInStore = LocalCheckInStore(fileURL: checkInURL)
        _ = cardStore.add(BrainDumpSuggestion(title: "Keep private", type: .task))
        try checkInStore.save(CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: []
        ))
        let exportURL = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: exportURL) }
        try FileManager.default.removeItem(at: checkInURL)
        try FileManager.default.createDirectory(at: checkInURL, withIntermediateDirectories: true)
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: checkInStore,
            reminderScheduler: reminderScheduler
        )
        services.iCloudSyncEnabled = true

        do {
            try await services.deleteAllLocalDataForPrivacy()
            XCTFail("Expected privacy deletion to surface the local persistence failure.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertTrue(services.iCloudSyncEnabled)
        XCTAssertFalse(reminderScheduler.cancelledAllFairNestReminders)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}

@MainActor
private final class CapturingReminderScheduler: ReminderScheduler {
    var scheduledCardIDs: [UUID] = []
    var cancelledCardIDs: [UUID] = []
    var pendingIdentifiers: [String] = []
    var scheduleDueTaskError: Error?
    var cancelledAllFairNestReminders = false

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func pendingFairNestReminderIdentifiers() async -> [String] {
        pendingIdentifiers
    }

    func scheduleDueTask(_ card: LoadCard) async throws {
        if let scheduleDueTaskError {
            throw scheduleDueTaskError
        }
        scheduledCardIDs.append(card.id)
        pendingIdentifiers.append(ReminderRequestFactory.cardReminderIdentifier(for: card.id))
    }

    func scheduleWeeklyCheckIn(weekday: Int, hour: Int, minute: Int) async throws {
        pendingIdentifiers.append(ReminderRequestFactory.weeklyCheckInIdentifier)
    }

    func cancelReminder(for cardID: UUID) async {
        cancelledCardIDs.append(cardID)
        pendingIdentifiers.removeAll { $0 == ReminderRequestFactory.cardReminderIdentifier(for: cardID) }
    }

    func cancelAllFairNestReminders() async {
        cancelledAllFairNestReminders = true
        pendingIdentifiers.removeAll()
    }
}

private enum TestReminderError: LocalizedError {
    case schedulingFailed

    var errorDescription: String? {
        "Could not schedule reminder"
    }
}
