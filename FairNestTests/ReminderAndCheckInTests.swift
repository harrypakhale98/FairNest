import CloudKit
import XCTest
import UserNotifications
@testable import FairNest

@MainActor
final class ReminderAndCheckInTests: XCTestCase {
    func testReminderFactoryBuildsDueTaskRequest() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let card = LoadCard(title: "Set out trash", type: .recurringResponsibility, dueDate: due)

        let request = ReminderRequestFactory.dueTaskRequest(for: card, now: due.addingTimeInterval(-3600))

        XCTAssertEqual(request?.title, "Shared responsibility")
        XCTAssertEqual(request?.body, "Open FairNest to review this item.")
        XCTAssertFalse(request?.body.contains("Set out trash") ?? true)
        XCTAssertEqual(request?.repeats, false)
    }

    func testReminderFactorySkipsPastDueTaskRequest() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let card = LoadCard(title: "Overdue", status: .planned, dueDate: now.addingTimeInterval(-60))

        XCTAssertNil(ReminderRequestFactory.dueTaskRequest(for: card, now: now))
        XCTAssertFalse(ReminderRequestFactory.shouldScheduleDueTask(for: card, now: now))
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

    func testWeeklyCheckInSaveFailureRestoresChangedCardsAndRethrowsOriginalError() {
        let previousCards = [LoadCard(title: "Trash", owner: .me)]
        let updatedCards = [LoadCard(title: "Trash", owner: .partner)]
        var didRestoreCards = false

        XCTAssertThrowsError(try WeeklyCheckInSaveCoordinator.handleCheckInSaveFailure(
            previousCards: previousCards,
            updatedCards: updatedCards,
            originalError: TestCheckInPersistenceError.checkInSaveFailed
        ) {
            didRestoreCards = true
        }) { error in
            XCTAssertEqual(error as? TestCheckInPersistenceError, .checkInSaveFailed)
        }
        XCTAssertTrue(didRestoreCards)
    }

    func testWeeklyCheckInSaveFailureSurfacesRollbackFailureDetails() {
        let previousCards = [LoadCard(title: "Trash", owner: .me)]
        let updatedCards = [LoadCard(title: "Trash", owner: .partner)]

        XCTAssertThrowsError(try WeeklyCheckInSaveCoordinator.handleCheckInSaveFailure(
            previousCards: previousCards,
            updatedCards: updatedCards,
            originalError: TestCheckInPersistenceError.checkInSaveFailed
        ) {
            throw TestCheckInPersistenceError.cardRollbackFailed
        }) { error in
            XCTAssertTrue(error is WeeklyCheckInSaveError)
            XCTAssertTrue(error.localizedDescription.contains("Could not save check-in"))
            XCTAssertTrue(error.localizedDescription.contains("Could not restore cards"))
        }
    }

    func testWeeklyCheckInSaveRunsCardSideEffectsAfterBothStoresPersist() async throws {
        let reminderScheduler = CapturingReminderScheduler()
        let syncEngine = CheckInCapturingSyncEngine()
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        let card = LoadCard(
            title: "Trash",
            owner: .me,
            status: .planned,
            dueDate: Date(timeIntervalSinceNow: 3600)
        )
        try cardStore.replaceAllThrowing(with: [card])
        let change = OwnershipChange(title: "Trash", owner: .partner, reason: "Reviewed")
        let record = CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: [change]
        )
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: checkInStore,
            reminderScheduler: reminderScheduler,
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        try await services.saveWeeklyCheckIn(record, applying: [change])

        XCTAssertEqual(checkInStore.records, [record])
        XCTAssertEqual(cardStore.cards.first?.owner, .partner)
        XCTAssertEqual(reminderScheduler.scheduledCardIDs, [card.id])
        XCTAssertEqual(syncEngine.uploadedBatches.count, 1)
        XCTAssertEqual(syncEngine.uploadedBatches.first?.first?.owner, .partner)
    }

    func testWeeklyCheckInSaveFailureSuppressesTransientCardSideEffects() async throws {
        let reminderScheduler = CapturingReminderScheduler()
        let syncEngine = CheckInCapturingSyncEngine()
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInURL = tempURL()
        let checkInStore = LocalCheckInStore(fileURL: checkInURL)
        let card = LoadCard(
            title: "Trash",
            owner: .me,
            status: .planned,
            dueDate: Date(timeIntervalSinceNow: 3600)
        )
        try cardStore.replaceAllThrowing(with: [card])
        try FileManager.default.createDirectory(at: checkInURL, withIntermediateDirectories: true)
        let change = OwnershipChange(title: "Trash", owner: .partner, reason: "Reviewed")
        let updatedCards = WeeklyCheckInEngine.cardsAfterApplying([change], to: [card])
        let record = CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: [change]
        )
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: checkInStore,
            reminderScheduler: reminderScheduler,
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        do {
            try await services.saveWeeklyCheckIn(record, applying: [change])
            XCTFail("Expected failing check-in persistence to roll back board changes.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        await services.handleCardsChanged(updatedCards)
        await services.handleCardsChanged(cardStore.cards)

        XCTAssertTrue(checkInStore.records.isEmpty)
        XCTAssertEqual(cardStore.cards.first?.owner, .me)
        XCTAssertTrue(reminderScheduler.scheduledCardIDs.isEmpty)
        XCTAssertTrue(reminderScheduler.cancelledCardIDs.isEmpty)
        XCTAssertTrue(syncEngine.uploadedBatches.isEmpty)
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

    func testSchedulingCurrentCardsCancelsPastDueReminder() async throws {
        let reminderScheduler = CapturingReminderScheduler()
        let overdueCard = LoadCard(title: "Overdue", status: .planned, dueDate: Date(timeIntervalSinceNow: -3600))
        reminderScheduler.pendingIdentifiers = [
            ReminderRequestFactory.cardReminderIdentifier(for: overdueCard.id)
        ]
        let cardStore = LocalCardStore(fileURL: tempURL())
        cardStore.upsert(overdueCard)
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            reminderScheduler: reminderScheduler
        )

        try await services.scheduleRemindersForCurrentCards()

        XCTAssertEqual(reminderScheduler.cancelledCardIDs, [overdueCard.id])
        XCTAssertTrue(reminderScheduler.scheduledCardIDs.isEmpty)
    }

    func testSchedulingCurrentCardsCancelsStaleRemindersWhenPermissionOff() async throws {
        let reminderScheduler = CapturingReminderScheduler()
        reminderScheduler.authorizationStatusValue = .denied
        let orphanedCardID = UUID()
        let overdueCard = LoadCard(title: "Overdue", status: .planned, dueDate: Date(timeIntervalSinceNow: -3600))
        reminderScheduler.pendingIdentifiers = [
            ReminderRequestFactory.cardReminderIdentifier(for: orphanedCardID),
            ReminderRequestFactory.cardReminderIdentifier(for: overdueCard.id)
        ]
        let cardStore = LocalCardStore(fileURL: tempURL())
        cardStore.upsert(overdueCard)
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            reminderScheduler: reminderScheduler
        )

        try await services.scheduleRemindersForCurrentCards()

        XCTAssertEqual(reminderScheduler.cancelledCardIDs, [orphanedCardID, overdueCard.id])
        XCTAssertTrue(reminderScheduler.scheduledCardIDs.isEmpty)
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
    var authorizationStatusValue: UNAuthorizationStatus = .authorized

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusValue
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

@MainActor
private final class CheckInCapturingSyncEngine: SyncService {
    var status: SyncStatus = .available
    var accountIdentifier: String?
    var remoteCards: [LoadCard] = []
    var uploadedBatches: [[LoadCard]] = []
    var fetchCount = 0
    var pinnedCardIDs = Set<UUID>()

    func refreshStatus() async {}

    func merge(local: [LoadCard], remote: [LoadCard]) -> [LoadCard] {
        ConflictResolver.merge(local: local, remote: remote)
    }

    func upload(cards: [LoadCard]) async throws {
        uploadedBatches.append(cards)
    }

    func fetchCards() async throws -> [LoadCard] {
        fetchCount += 1
        return remoteCards
    }

    func synchronize(local cards: [LoadCard]) async throws -> [LoadCard] {
        let merged = merge(local: cards, remote: remoteCards)
        try await upload(cards: merged)
        return merged
    }

    func deleteSharedHouseholdData() async throws -> CloudKitHouseholdDeletionResult {
        .empty
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {}

    func pinCardsToPrivateDatabase(_ cardIDs: Set<UUID>) {
        pinnedCardIDs.formUnion(cardIDs)
    }
}

private enum TestReminderError: LocalizedError {
    case schedulingFailed

    var errorDescription: String? {
        "Could not schedule reminder"
    }
}

private enum TestCheckInPersistenceError: LocalizedError {
    case checkInSaveFailed
    case cardRollbackFailed

    var errorDescription: String? {
        switch self {
        case .checkInSaveFailed:
            return "Could not save check-in"
        case .cardRollbackFailed:
            return "Could not restore cards"
        }
    }
}
