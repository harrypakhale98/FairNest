import Foundation

enum ParserSource: String, Codable, Equatable {
    case ruleBased
    case foundationModels
}

struct BrainDumpContext: Equatable {
    var defaultOwner: CardOwner
    var today: Date
    var locale: Locale

    init(defaultOwner: CardOwner = .unassigned, today: Date = Date(), locale: Locale = .current) {
        self.defaultOwner = defaultOwner
        self.today = today
        self.locale = locale
    }
}

struct BrainDumpSuggestion: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var type: CardType
    var owner: CardOwner
    var effort: Effort
    var dueDate: Date?
    var recurrence: Recurrence
    var notes: String
    var doneCriteria: String
    var sourceSnippet: String

    init(
        id: UUID = UUID(),
        title: String,
        type: CardType,
        owner: CardOwner = .unassigned,
        effort: Effort = .medium,
        dueDate: Date? = nil,
        recurrence: Recurrence = .none,
        notes: String = "",
        doneCriteria: String = "",
        sourceSnippet: String = ""
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        self.owner = owner
        self.effort = effort
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.notes = notes
        self.doneCriteria = doneCriteria
        self.sourceSnippet = sourceSnippet
    }

    func makeCard(createdBy: HouseholdMember = .me, at date: Date = Date()) -> LoadCard {
        LoadCard(
            title: title,
            type: type,
            owner: owner,
            status: .inbox,
            effort: effort,
            dueDate: dueDate,
            recurrence: recurrence,
            notes: notes,
            doneCriteria: doneCriteria,
            createdBy: createdBy,
            createdAt: date,
            modifiedBy: createdBy,
            updatedAt: date
        )
    }
}

struct SafetyNotice: Codable, Equatable {
    var title: String
    var message: String
}

struct BrainDumpParseResult: Codable, Equatable {
    var suggestions: [BrainDumpSuggestion]
    var safetyNotice: SafetyNotice?
    var source: ParserSource

    var hasSafetyIntervention: Bool {
        safetyNotice != nil
    }
}
