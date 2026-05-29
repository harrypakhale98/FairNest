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

    var allowedEditorTransitions: [CardStatus] {
        Self.allCases.filter { canTransition(to: $0) }
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
            let clampedDay = max(1, min(31, day))
            if clampedDay > 28 {
                return "Monthly on day \(clampedDay) or last day"
            }
            return "Monthly on day \(clampedDay)"
        }
    }

    var isRecurring: Bool {
        if case .none = self { return false }
        return true
    }

    func nextDate(after date: Date, preservingTimeFrom timeSource: Date? = nil, calendar: Calendar = .current) -> Date? {
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: timeSource ?? date)
        let hour = timeComponents.hour ?? 0
        let minute = timeComponents.minute ?? 0
        let second = timeComponents.second ?? 0
        let nanosecond = timeComponents.nanosecond ?? 0

        switch self {
        case .none:
            return nil
        case .daily:
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            var components = calendar.dateComponents([.year, .month, .day], from: nextDay)
            components.hour = hour
            components.minute = minute
            components.second = second
            components.nanosecond = nanosecond
            guard let candidate = calendar.date(from: components) else { return nil }
            if candidate > date { return candidate }
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        case .weekly(let weekday):
            var components = DateComponents()
            components.weekday = max(1, min(7, weekday))
            components.hour = hour
            components.minute = minute
            components.second = second
            components.nanosecond = nanosecond
            return calendar.nextDate(
                after: date,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        case .monthly(let day):
            let requestedDay = max(1, min(31, day))
            return nextMonthlyDate(
                after: date,
                requestedDay: requestedDay,
                hour: hour,
                minute: minute,
                second: second,
                nanosecond: nanosecond,
                calendar: calendar
            )
        }
    }

    private func nextMonthlyDate(
        after date: Date,
        requestedDay: Int,
        hour: Int,
        minute: Int,
        second: Int,
        nanosecond: Int,
        calendar: Calendar
    ) -> Date? {
        let baseComponents = calendar.dateComponents([.year, .month], from: date)
        guard let baseYear = baseComponents.year, let baseMonth = baseComponents.month else { return nil }

        for offset in 0...24 {
            var monthComponents = DateComponents()
            monthComponents.year = baseYear
            monthComponents.month = baseMonth + offset
            monthComponents.day = 1
            guard let firstOfMonth = calendar.date(from: monthComponents),
                  let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
                continue
            }

            var candidateComponents = calendar.dateComponents([.year, .month], from: firstOfMonth)
            candidateComponents.day = min(requestedDay, dayRange.count)
            candidateComponents.hour = hour
            candidateComponents.minute = minute
            candidateComponents.second = second
            candidateComponents.nanosecond = nanosecond

            if let candidate = calendar.date(from: candidateComponents), candidate > date {
                return candidate
            }
        }

        return nil
    }
}

enum CardSyncOrigin: String, Codable, Equatable, Hashable {
    case local
    case privateCloud
    case sharedCloud

    var isSharedCloud: Bool {
        self == .sharedCloud
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
    var syncOrigin: CardSyncOrigin

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
        deletedAt: Date? = nil,
        syncOrigin: CardSyncOrigin = .local
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
        self.syncOrigin = syncOrigin
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case owner
        case status
        case effort
        case dueDate
        case recurrence
        case notes
        case doneCriteria
        case createdBy
        case createdAt
        case modifiedBy
        case updatedAt
        case deletedAt
        case syncOrigin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            type: try container.decode(CardType.self, forKey: .type),
            owner: try container.decode(CardOwner.self, forKey: .owner),
            status: try container.decode(CardStatus.self, forKey: .status),
            effort: try container.decode(Effort.self, forKey: .effort),
            dueDate: try container.decodeIfPresent(Date.self, forKey: .dueDate),
            recurrence: try container.decode(Recurrence.self, forKey: .recurrence),
            notes: try container.decode(String.self, forKey: .notes),
            doneCriteria: try container.decode(String.self, forKey: .doneCriteria),
            createdBy: try container.decode(HouseholdMember.self, forKey: .createdBy),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            modifiedBy: try container.decode(HouseholdMember.self, forKey: .modifiedBy),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            syncOrigin: try container.decodeIfPresent(CardSyncOrigin.self, forKey: .syncOrigin) ?? .local
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encode(owner, forKey: .owner)
        try container.encode(status, forKey: .status)
        try container.encode(effort, forKey: .effort)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(recurrence, forKey: .recurrence)
        try container.encode(notes, forKey: .notes)
        try container.encode(doneCriteria, forKey: .doneCriteria)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedBy, forKey: .modifiedBy)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(syncOrigin, forKey: .syncOrigin)
    }

    var isDeleted: Bool { deletedAt != nil }

    var redactedDeletionTombstone: LoadCard {
        guard isDeleted else { return self }
        let markerDate = deletedAt ?? updatedAt
        return LoadCard(
            id: id,
            title: "",
            type: .task,
            owner: .unassigned,
            status: .done,
            effort: .tiny,
            dueDate: nil,
            recurrence: .none,
            notes: "",
            doneCriteria: "",
            createdBy: .system,
            createdAt: markerDate,
            modifiedBy: .system,
            updatedAt: markerDate,
            deletedAt: markerDate,
            syncOrigin: syncOrigin
        )
    }

    func normalizedForLocalSave(by member: HouseholdMember = .me, at date: Date = Date()) -> LoadCard {
        var copy = self
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.modifiedBy = member
        copy.updatedAt = date
        return copy
    }

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
        let recurrenceAnchor = dueDate.map { max($0, date) } ?? date
        if next == .done, let nextDue = recurrence.nextDate(after: recurrenceAnchor, preservingTimeFrom: dueDate ?? date) {
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
        self = redactedDeletionTombstone
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
