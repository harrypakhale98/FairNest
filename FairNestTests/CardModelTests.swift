import XCTest
@testable import FairNest

final class CardModelTests: XCTestCase {
    func testRecurrenceComputesNextDailyDate() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let next = Recurrence.daily.nextDate(after: start, calendar: Calendar(identifier: .gregorian))

        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, start)
    }

    func testStatusTransitionsRejectInvalidDoneToWaiting() {
        var card = LoadCard(title: "Trash", status: .done)

        XCTAssertThrowsError(try card.transition(to: .waiting))
        XCTAssertNoThrow(try card.transition(to: .planned))
    }

    func testCompletingRecurringCardAdvancesDueDateInsteadOfClosingForever() throws {
        let now = Date()
        var card = LoadCard(title: "Water plants", status: .planned, dueDate: now, recurrence: .daily)

        try card.transition(to: .done, at: now)

        XCTAssertEqual(card.status, .planned)
        XCTAssertNotNil(card.dueDate)
        XCTAssertGreaterThan(card.dueDate!, now)
    }
}
