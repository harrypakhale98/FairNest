import Foundation
import WidgetKit

enum FairNestShared {
    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "FairNestAppGroupIdentifier") as? String ?? "group.com.example.fairnest"
    }
    static let widgetSnapshotKey = "FairNestWidgetSnapshot"
    static let homeWidgetKind = "FairNestHomeWidget"
    static let lockScreenWidgetKind = "FairNestLockScreenWidget"

    static var sharedDefaults: UserDefaults? {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        assert(defaults != nil, "FairNest App Group defaults are unavailable.")
        return defaults
    }
}

struct WidgetCardSummary: Codable, Equatable, Identifiable {
    var id: UUID
    var type: CardType
    var owner: CardOwner
    var effort: Effort
    var dueDate: Date?
    var status: CardStatus
    var displayTitle: String

    init(
        id: UUID,
        type: CardType,
        owner: CardOwner,
        effort: Effort,
        dueDate: Date?,
        status: CardStatus,
        displayTitle: String? = nil
    ) {
        self.id = id
        self.type = type
        self.owner = owner
        self.effort = effort
        self.dueDate = dueDate
        self.status = status
        self.displayTitle = displayTitle ?? Self.safeTitle(for: type)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case owner
        case effort
        case dueDate
        case status
        case displayTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(CardType.self, forKey: .type)
        owner = try container.decode(CardOwner.self, forKey: .owner)
        effort = try container.decode(Effort.self, forKey: .effort)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        status = try container.decode(CardStatus.self, forKey: .status)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle) ?? Self.safeTitle(for: type)
    }

    private static func safeTitle(for type: CardType) -> String {
        switch type {
        case .task: return "Task"
        case .recurringResponsibility: return "Shared responsibility"
        case .decision: return "Decision"
        case .reminder: return "Reminder"
        case .conversation: return "Conversation"
        case .appreciation: return "Appreciation"
        }
    }
}

struct WidgetHouseholdSnapshot: Codable, Equatable {
    var generatedAt: Date
    var syncPending: Bool
    var cards: [WidgetCardSummary]

    static let empty = WidgetHouseholdSnapshot(generatedAt: Date(), syncPending: false, cards: [])

    var nextResponsibility: WidgetCardSummary? {
        cards
            .filter { $0.status != .done }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.effort > rhs.effort
                }
            }
            .first
    }

    var todayCards: [WidgetCardSummary] {
        cards.filter { card in
            guard card.status != .done else { return false }
            guard let dueDate = card.dueDate else { return card.status == .doing || card.status == .inbox }
            return Calendar.current.isDateInToday(dueDate) || dueDate < Date()
        }
    }

    var weeklyEffort: Int {
        cards
            .filter { $0.status != .done }
            .reduce(0) { $0 + $1.effort.rawValue }
    }
}

enum WidgetSnapshotStore {
    static func write(cards: [LoadCard], syncPending: Bool = false, date: Date = Date()) {
        let summaries = summaries(for: cards)
        let snapshot = WidgetHouseholdSnapshot(generatedAt: date, syncPending: syncPending, cards: summaries)
        if let data = try? JSONEncoder.fairNest.encode(snapshot) {
            FairNestShared.sharedDefaults?.set(data, forKey: FairNestShared.widgetSnapshotKey)
        }
    }

    static func summaries(for cards: [LoadCard]) -> [WidgetCardSummary] {
        cards
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.updatedAt > rhs.updatedAt
                }
            }
            .prefix(25)
            .map {
                WidgetCardSummary(
                    id: $0.id,
                    type: $0.type,
                    owner: $0.owner,
                    effort: $0.effort,
                    dueDate: $0.dueDate,
                    status: $0.status
                )
            }
    }

    static func read() -> WidgetHouseholdSnapshot {
        guard let data = FairNestShared.sharedDefaults?.data(forKey: FairNestShared.widgetSnapshotKey),
              let snapshot = try? JSONDecoder.fairNest.decode(WidgetHouseholdSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: FairNestShared.homeWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: FairNestShared.lockScreenWidgetKind)
    }
}

extension JSONEncoder {
    static var fairNest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var fairNest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
