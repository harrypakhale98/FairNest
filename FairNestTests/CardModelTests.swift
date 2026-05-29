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

    func testEditorStatusOptionsMatchAllowedTransitions() {
        XCTAssertEqual(CardStatus.done.allowedEditorTransitions, [.inbox, .planned, .doing, .done])
        XCTAssertEqual(CardStatus.inbox.allowedEditorTransitions, CardStatus.allCases)
    }

    func testCompletingRecurringCardAdvancesDueDateInsteadOfClosingForever() throws {
        let now = Date()
        var card = LoadCard(title: "Water plants", status: .planned, dueDate: now, recurrence: .daily)

        try card.transition(to: .done, at: now)

        XCTAssertEqual(card.status, .planned)
        XCTAssertNotNil(card.dueDate)
        XCTAssertGreaterThan(card.dueDate!, now)
    }

    func testCompletingFutureDailyRecurringCardAdvancesAfterScheduledDueDate() throws {
        let calendar = Calendar.current
        let completedAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 9, minute: 0))!
        let dueDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 18, minute: 30))!
        var card = LoadCard(title: "Reset vitamins", status: .planned, dueDate: dueDate, recurrence: .daily)

        try card.transition(to: .done, at: completedAt)

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: card.dueDate!)
        XCTAssertEqual(card.status, .planned)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 29)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 30)
        XCTAssertGreaterThan(card.dueDate!, dueDate)
    }

    func testCompletingWeeklyRecurringCardPreservesScheduledTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dueDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 18, minute: 30))!
        let completedAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 9, minute: 0))!
        var card = LoadCard(title: "Trash", status: .planned, dueDate: dueDate, recurrence: .weekly(weekday: 2))

        try card.transition(to: .done, at: completedAt)

        let components = calendar.dateComponents([.weekday, .hour, .minute], from: card.dueDate!)
        XCTAssertEqual(components.weekday, 2)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 30)
        XCTAssertGreaterThan(card.dueDate!, completedAt)
    }

    func testMonthlyRecurrenceUsesLastDayWhenMonthIsShort() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let januaryThirtyFirst = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 18, minute: 30))!

        let next = Recurrence.monthly(day: 31).nextDate(after: januaryThirtyFirst, calendar: calendar)

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 30)
    }
}

final class BoardEmptyStateTests: XCTestCase {
    func testFilteredEmptyStateShowsAllWhenCardsExistElsewhere() {
        let state = BoardEmptyState.make(filter: .today, activeCardCount: 2)

        XCTAssertEqual(state.title, "No cards in this view")
        XCTAssertEqual(state.description, "You have 2 cards in other views.")
        XCTAssertEqual(state.actionTitle, "Show All")
        XCTAssertEqual(state.action, .showAll)
    }

    func testTrulyEmptyBoardStartsWithAddCard() {
        let state = BoardEmptyState.make(filter: .all, activeCardCount: 0)

        XCTAssertEqual(state.title, "No cards yet")
        XCTAssertEqual(state.actionTitle, "Add Card")
        XCTAssertEqual(state.action, .addCard)
    }
}

final class BoardFilterTests: XCTestCase {
    func testDecisionsFilterShowsOnlyOpenDecisions() {
        let openDecision = LoadCard(title: "Pick cleaner", type: .decision, status: .inbox)
        let doneDecision = LoadCard(title: "Picked cleaner", type: .decision, status: .done)
        let openTask = LoadCard(title: "Book cleaner", type: .task, status: .inbox)

        XCTAssertTrue(BoardFilter.decisions.includes(openDecision))
        XCTAssertFalse(BoardFilter.decisions.includes(doneDecision))
        XCTAssertFalse(BoardFilter.decisions.includes(openTask))
    }
}
