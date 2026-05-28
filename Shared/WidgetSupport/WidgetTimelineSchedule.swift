import Foundation

enum WidgetTimelineSchedule {
    static func reloadDates(now: Date, intervalMinutes: Int = 30) -> [Date] {
        [
            now,
            Calendar.current.date(byAdding: .minute, value: intervalMinutes, to: now) ?? now.addingTimeInterval(TimeInterval(intervalMinutes * 60))
        ]
    }
}
