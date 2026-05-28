import Foundation
import UserNotifications

@MainActor
protocol ReminderScheduler {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func scheduleDueTask(_ card: LoadCard) async throws
    func scheduleWeeklyCheckIn(weekday: Int, hour: Int, minute: Int) async throws
    func cancelReminder(for cardID: UUID) async
}

struct ReminderRequest: Equatable {
    var identifier: String
    var title: String
    var body: String
    var dateComponents: DateComponents
    var repeats: Bool
}

enum ReminderRequestFactory {
    static func dueTaskRequest(for card: LoadCard, calendar: Calendar = .current) -> ReminderRequest? {
        guard let dueDate = card.dueDate else { return nil }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        return ReminderRequest(
            identifier: "card-\(card.id.uuidString)",
            title: card.type == .recurringResponsibility ? "Shared responsibility" : "FairNest reminder",
            body: card.title,
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
            identifier: "weekly-check-in",
            title: "Weekly check-in",
            body: "Take 10 quiet minutes to rebalance the home load.",
            dateComponents: components,
            repeats: true
        )
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

    func scheduleDueTask(_ card: LoadCard) async throws {
        guard let reminder = ReminderRequestFactory.dueTaskRequest(for: card) else { return }
        try await schedule(reminder)
    }

    func scheduleWeeklyCheckIn(weekday: Int, hour: Int, minute: Int) async throws {
        try await schedule(ReminderRequestFactory.weeklyCheckInRequest(weekday: weekday, hour: hour, minute: minute))
    }

    func cancelReminder(for cardID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: ["card-\(cardID.uuidString)"])
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
