import Foundation
import UserNotifications

@MainActor
protocol ReminderScheduler {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingFairNestReminderIdentifiers() async -> [String]
    func scheduleDueTask(_ card: LoadCard) async throws
    func scheduleWeeklyCheckIn(weekday: Int, hour: Int, minute: Int) async throws
    func cancelReminder(for cardID: UUID) async
    func cancelAllFairNestReminders() async
}

struct ReminderRequest: Equatable {
    var identifier: String
    var title: String
    var body: String
    var dateComponents: DateComponents
    var repeats: Bool
}

enum ReminderRequestFactory {
    static let weeklyCheckInIdentifier = "weekly-check-in"
    static let cardReminderIdentifierPrefix = "card-"

    static func cardReminderIdentifier(for cardID: UUID) -> String {
        "\(cardReminderIdentifierPrefix)\(cardID.uuidString)"
    }

    static func cardID(fromReminderIdentifier identifier: String) -> UUID? {
        guard isCardReminderIdentifier(identifier) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(cardReminderIdentifierPrefix.count)))
    }

    static func shouldScheduleDueTask(for card: LoadCard, now: Date = Date()) -> Bool {
        guard !card.isDeleted, card.status != .done, let dueDate = card.dueDate else { return false }
        return dueDate > now
    }

    static func dueTaskRequest(for card: LoadCard, calendar: Calendar = .current, now: Date = Date()) -> ReminderRequest? {
        guard shouldScheduleDueTask(for: card, now: now), let dueDate = card.dueDate else { return nil }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        return ReminderRequest(
            identifier: cardReminderIdentifier(for: card.id),
            title: card.type == .recurringResponsibility ? "Shared responsibility" : "FairNest reminder",
            body: "Open FairNest to review this item.",
            dateComponents: components,
            repeats: false
        )
    }

    static func weeklyCheckInRequest(weekday: Int, hour: Int, minute: Int) -> ReminderRequest {
        var components = DateComponents()
        components.weekday = max(1, min(7, weekday))
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))
        return ReminderRequest(
            identifier: weeklyCheckInIdentifier,
            title: "Weekly check-in",
            body: "Take 10 quiet minutes to rebalance the home load.",
            dateComponents: components,
            repeats: true
        )
    }

    static func isFairNestReminderIdentifier(_ identifier: String) -> Bool {
        identifier == weeklyCheckInIdentifier || isCardReminderIdentifier(identifier)
    }

    static func isCardReminderIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(cardReminderIdentifierPrefix)
    }
}

struct LocalReminderScheduler: ReminderScheduler {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func pendingFairNestReminderIdentifiers() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(ReminderRequestFactory.isFairNestReminderIdentifier)
            .sorted()
    }

    func scheduleDueTask(_ card: LoadCard) async throws {
        guard let reminder = ReminderRequestFactory.dueTaskRequest(for: card) else { return }
        try await schedule(reminder)
    }

    func scheduleWeeklyCheckIn(weekday: Int, hour: Int, minute: Int) async throws {
        try await schedule(ReminderRequestFactory.weeklyCheckInRequest(weekday: weekday, hour: hour, minute: minute))
    }

    func cancelReminder(for cardID: UUID) async {
        let identifiers = [ReminderRequestFactory.cardReminderIdentifier(for: cardID)]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAllFairNestReminders() async {
        let pendingIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(ReminderRequestFactory.isFairNestReminderIdentifier)
        let deliveredIdentifiers = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter(ReminderRequestFactory.isFairNestReminderIdentifier)
        let identifiers = Array(Set(pendingIdentifiers + deliveredIdentifiers + [ReminderRequestFactory.weeklyCheckInIdentifier]))
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func schedule(_ reminder: ReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.dateComponents, repeats: reminder.repeats)
        let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

}
