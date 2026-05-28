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
        XCTAssertEqual(request?.body, "Set out trash")
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

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}

@MainActor
private final class CapturingReminderScheduler: ReminderScheduler {
    var scheduledCardIDs: [UUID] = []
    var cancelledCardIDs: [UUID] = []

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func scheduleDueTask(_ card: LoadCard) async throws {
        scheduledCardIDs.append(card.id)
    }

    func scheduleWeeklyCheckIn(weekday: Int, hour: Int, minute: Int) async throws {}

    func cancelReminder(for cardID: UUID) async {
        cancelledCardIDs.append(cardID)
    }
}
