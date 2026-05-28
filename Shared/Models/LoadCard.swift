import Foundation

enum CardType: String, Codable, CaseIterable, Identifiable, Hashable {
    case task
    case recurringResponsibility
    case decision
    case reminder
    case conversation
    case appreciation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .task: return "Task"
        case .recurringResponsibility: return "Recurring"
        case .decision: return "Decision"
        case .reminder: return "Reminder"
        case .conversation: return "Conversation"
        case .appreciation: return "Appreciation"
        }
    }

    var symbolName: String {
        switch self {
        case .task: return "checklist"
        case .recurringResponsibility: return "arrow.trianglehead.2.clockwise"
        case .decision: return "questionmark.diamond"
        case .reminder: return "bell"
        case .conversation: return "bubble.left.and.bubble.right"
        case .appreciation: return "heart"
        }
    }
}

enum CardOwner: String, Codable, CaseIterable, Identifiable, Hashable {
    case unassigned
    case me
    case partner
    case shared

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .me: return "Me"
        case .partner: return "Partner"
        case .shared: return "Shared"
        }
    }

    var symbolName: String {
        switch self {
        case .unassigned: return "person.crop.circle.badge.questionmark"
        case .me: return "person"
        case .partner: return "person.2"
        case .shared: return "person.2.fill"
        }
    }
}

enum CardStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case inbox
    case planned
    case doing
    case waiting
    case done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inbox: return "Inbox"
        case .planned: return "Planned"
        case .doing: return "Doing"
        case .waiting: return "Waiting"
        case .done: return "Done"
        }
    }

    func canTransition(to next: CardStatus) -> Bool {
        if self == next { return true }
        switch self {
        case .inbox:
            return [.planned, .doing, .waiting, .done].contains(next)
        case .planned:
            return [.inbox, .doing, .waiting, .done].contains(next)
        case .doing:
            return [.planned, .waiting, .done].contains(next)
        case .waiting:
            return [.planned, .doing, .done].contains(next)
        case .done:
            return [.planned, .doing, .inbox].contains(next)
        }
    }
}

enum Effort: Int, Codable, CaseIterable, Identifiable, Hashable, Comparable {
    case tiny = 1
    case light = 2
    case medium = 3
    case heavy = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .tiny: return "Tiny"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }

    static func < (lhs: Effort, rhs: Effort) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum HouseholdMember: String, Codable, CaseIterable, Identifiable, Hashable {
    case me
    case partner
    case system

    var id: String { rawValue }
}

enum Recurrence: Codable, Equatable, Hashable {
    case none
    case daily
    case weekly(weekday: Int)
    case monthly(day: Int)

    var label: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .weekly(let weekday):
            let symbols = Calendar.current.weekdaySymbols
            let index = max(1, min(7, weekday)) - 1
            return "Weekly on \(symbols[index])"
        case .monthly(let day):
            return "Monthly on day \(day)"
        }
    }

    var isRecurring: Bool {
        if case .none = self { return false }
        return true
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        case .weekly(let weekday):
            var components = DateComponents()
            components.weekday = max(1, min(7, weekday))
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
        case .monthly(let day):
            let clampedDay = max(1, min(28, day))
            var components = DateComponents()
            components.day = clampedDay
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
        }
    }
}

struct LoadCard: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var type: CardType
    var owner: CardOwner
    var status: CardStatus
    var effort: Effort
    var dueDate: Date?
    var recurrence: Recurrence
    var notes: String
    var doneCriteria: String
    var createdBy: HouseholdMember
    var createdAt: Date
    var modifiedBy: HouseholdMember
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        type: CardType = .task,
        owner: CardOwner = .unassigned,
        status: CardStatus = .inbox,
        effort: Effort = .medium,
        dueDate: Date? = nil,
        recurrence: Recurrence = .none,
        notes: String = "",
        doneCriteria: String = "",
        createdBy: HouseholdMember = .me,
        createdAt: Date = Date(),
        modifiedBy: HouseholdMember = .me,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        self.owner = owner
        self.status = status
        self.effort = effort
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.notes = notes
        self.doneCriteria = doneCriteria
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.modifiedBy = modifiedBy
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isDeleted: Bool { deletedAt != nil }

    var isActionableToday: Bool {
        guard !isDeleted, status != .done else { return false }
        guard let dueDate else { return status == .inbox || status == .doing }
        return Calendar.current.startOfDay(for: dueDate) <= Calendar.current.startOfDay(for: Date())
    }

    mutating func transition(to next: CardStatus, by member: HouseholdMember = .me, at date: Date = Date()) throws {
        guard status.canTransition(to: next) else {
            throw CardTransitionError.invalidTransition(from: status, to: next)
        }
        status = next
        modifiedBy = member
        updatedAt = date
        if next == .done, let nextDue = recurrence.nextDate(after: date) {
            status = .planned
            dueDate = nextDue
        }
    }

    mutating func reassign(to owner: CardOwner, by member: HouseholdMember = .me, at date: Date = Date()) {
        self.owner = owner
        modifiedBy = member
        updatedAt = date
    }

    mutating func snooze(days: Int, by member: HouseholdMember = .me, at date: Date = Date()) {
        dueDate = Calendar.current.date(byAdding: .day, value: days, to: dueDate ?? date)
        status = status == .done ? .planned : status
        modifiedBy = member
        updatedAt = date
    }

    mutating func softDelete(at date: Date = Date(), by member: HouseholdMember = .me) {
        deletedAt = date
        modifiedBy = member
        updatedAt = date
    }

    mutating func restore(at date: Date = Date(), by member: HouseholdMember = .me) {
        deletedAt = nil
        modifiedBy = member
        updatedAt = date
    }
}

enum CardTransitionError: LocalizedError, Equatable {
    case invalidTransition(from: CardStatus, to: CardStatus)

    var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let to):
            return "Cannot move a card from \(from.label) to \(to.label)."
        }
    }
}
