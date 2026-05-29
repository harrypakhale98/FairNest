import Foundation

@MainActor
protocol LoadCardStore: AnyObject {
    var cards: [LoadCard] { get }
    var activeCards: [LoadCard] { get }

    func load()
    func upsert(_ card: LoadCard)
    func upsertThrowing(_ card: LoadCard) throws
    func upsertThrowing(_ card: LoadCard, expectedRevision: CardRevision) throws
    func add(_ suggestion: BrainDumpSuggestion) -> LoadCard
    func transition(id: UUID, to status: CardStatus) throws
    func reassign(id: UUID, to owner: CardOwner)
    func reassignThrowing(id: UUID, to owner: CardOwner) throws
    func snooze(id: UUID, days: Int)
    func snoozeThrowing(id: UUID, days: Int) throws
    func delete(id: UUID)
    func deleteThrowing(id: UUID) throws
    func restore(id: UUID)
    func restoreThrowing(id: UUID) throws
    func exportData() throws -> Data
    func deleteAllLocalData()
}

enum LocalCardStoreError: LocalizedError {
    case persistenceFailed
    case cardDeleted
    case missingCard
    case restoreUnavailable
    case staleRestore
    case staleCardEdit
    case storeUnavailable

    var errorDescription: String? {
        switch self {
        case .persistenceFailed:
            return "FairNest could not save these cards. Your brain dump is still here. Try again."
        case .cardDeleted:
            return "This card was removed before your edit could be saved."
        case .missingCard:
            return "FairNest could not find that card."
        case .restoreUnavailable:
            return "FairNest no longer has the removed card details needed to restore it."
        case .staleRestore:
            return "This card changed after it was removed. FairNest left the newer removal in place."
        case .staleCardEdit:
            return FairNestIssueCopy.staleCardEdit
        case .storeUnavailable:
            return "FairNest could not read the local card store. Close and reopen FairNest after unlocking this iPhone, then try again."
        }
    }
}

struct CardRevision: Equatable {
    var updatedAt: Date
    var deletedAt: Date?

    init(card: LoadCard) {
        updatedAt = card.updatedAt
        deletedAt = card.deletedAt
    }
}

struct CardStoreEnvelope: Codable, Equatable {
    var version: Int
    var exportedAt: Date
    var cards: [LoadCard]
}

@MainActor
final class LocalCardStore: ObservableObject, LoadCardStore {
    @Published private(set) var cards: [LoadCard] = []
    @Published private(set) var lastLoadErrorMessage: String?
    @Published private(set) var lastPersistenceErrorMessage: String?

    private let fileURL: URL
    private let fileManager: FileManager
    private var storeUnavailableDueToLoadFailure = false

    var isUnavailableDueToLoadFailure: Bool {
        storeUnavailableDueToLoadFailure
    }

    var activeCards: [LoadCard] {
        cards.filter { !$0.isDeleted }
    }

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("FairNest", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("cards.json")
        }
        if ProcessInfo.processInfo.arguments.contains("-resetFairNest") {
            try? fileManager.removeItem(at: self.fileURL)
            removeCorruptBackupsBestEffort()
        }
        load()
        if ProcessInfo.processInfo.arguments.contains("-seedDemoData"), cards.isEmpty {
            cards = Self.sampleCards()
            persist()
        }
    }

    func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cards = []
            persist()
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            cards = []
            WidgetSnapshotStore.clear()
            WidgetSnapshotStore.reloadTimelines()
            lastLoadErrorMessage = error.localizedDescription
            storeUnavailableDueToLoadFailure = true
            return
        }

        do {
            let envelope = try JSONDecoder.fairNest.decode(CardStoreEnvelope.self, from: data)
            cards = envelope.cards.sorted { $0.updatedAt > $1.updatedAt }
            lastLoadErrorMessage = nil
            storeUnavailableDueToLoadFailure = false
            WidgetSnapshotStore.write(cards: cards)
        } catch is DecodingError {
            backupCorruptStore()
            cards = []
            WidgetSnapshotStore.clear()
            WidgetSnapshotStore.reloadTimelines()
            lastLoadErrorMessage = "FairNest found an unreadable local card store and moved it aside."
            storeUnavailableDueToLoadFailure = false
        } catch {
            lastLoadErrorMessage = error.localizedDescription
            storeUnavailableDueToLoadFailure = true
        }
    }

    func upsert(_ card: LoadCard) {
        do {
            try upsertThrowing(card)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    func upsertThrowing(_ card: LoadCard) throws {
        try upsertThrowing(card, by: .me, at: Date())
    }

    func upsertThrowing(_ card: LoadCard, expectedRevision: CardRevision) throws {
        try upsertThrowing(card, by: .me, at: Date(), expectedRevision: expectedRevision)
    }

    func upsertThrowing(
        _ card: LoadCard,
        by member: HouseholdMember = .me,
        at date: Date = Date(),
        expectedRevision: CardRevision? = nil
    ) throws {
        try mutateAndPersist { cards in
            var savedCard = card.normalizedForLocalSave(by: member, at: date)
            if let index = cards.firstIndex(where: { $0.id == card.id }) {
                let existingCard = cards[index]
                if let expectedRevision, CardRevision(card: existingCard) != expectedRevision {
                    throw LocalCardStoreError.staleCardEdit
                }
                if existingCard.isDeleted && savedCard.deletedAt == nil {
                    throw LocalCardStoreError.cardDeleted
                }
                if existingCard.status != savedCard.status {
                    let requestedStatus = savedCard.status
                    savedCard.status = existingCard.status
                    try savedCard.transition(to: requestedStatus, by: member, at: date)
                }
                cards[index] = savedCard
            } else {
                cards.insert(savedCard, at: 0)
            }
        }
    }

    @discardableResult
    func add(_ suggestion: BrainDumpSuggestion) -> LoadCard {
        let card = suggestion.makeCard()
        upsert(card)
        return card
    }

    @discardableResult
    func addReviewed(_ suggestions: [BrainDumpSuggestion]) throws -> [LoadCard] {
        let createdCards = suggestions.map { $0.makeCard() }
        guard !createdCards.isEmpty else { return [] }

        try mutateAndPersist { cards in
            for card in createdCards {
                if let index = cards.firstIndex(where: { $0.id == card.id }) {
                    cards[index] = card
                } else {
                    cards.insert(card, at: 0)
                }
            }
        }

        return createdCards
    }

    func transition(id: UUID, to status: CardStatus) throws {
        try mutateAndPersist { cards in
            guard let index = cards.firstIndex(where: { $0.id == id }) else { throw LocalCardStoreError.missingCard }
            var card = cards[index]
            try card.transition(to: status)
            cards[index] = card
        }
    }

    func reassign(id: UUID, to owner: CardOwner) {
        do {
            try reassignThrowing(id: id, to: owner)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    func reassignThrowing(id: UUID, to owner: CardOwner) throws {
        try mutateAndPersist { cards in
            guard let index = cards.firstIndex(where: { $0.id == id }) else { throw LocalCardStoreError.missingCard }
            cards[index].reassign(to: owner)
        }
    }

    func snooze(id: UUID, days: Int) {
        do {
            try snoozeThrowing(id: id, days: days)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    func snoozeThrowing(id: UUID, days: Int) throws {
        try mutateAndPersist { cards in
            guard let index = cards.firstIndex(where: { $0.id == id }) else { throw LocalCardStoreError.missingCard }
            cards[index].snooze(days: days)
        }
    }

    func delete(id: UUID) {
        do {
            try deleteThrowing(id: id)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    func deleteThrowing(id: UUID) throws {
        try mutateAndPersist { cards in
            guard let index = cards.firstIndex(where: { $0.id == id }) else { throw LocalCardStoreError.missingCard }
            cards[index].softDelete()
        }
    }

    func restore(id: UUID) {
        do {
            try restoreThrowing(id: id)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    func restoreThrowing(id: UUID) throws {
        try mutateAndPersist { cards in
            guard let index = cards.firstIndex(where: { $0.id == id }) else { throw LocalCardStoreError.missingCard }
            guard cards[index].isDeleted else { return }
            guard !cards[index].title.isEmpty else { throw LocalCardStoreError.restoreUnavailable }
            cards[index].restore()
        }
    }

    func restoreThrowing(
        _ card: LoadCard,
        matchingDeletedAt deletedAt: Date? = nil,
        by member: HouseholdMember = .me,
        at date: Date = Date()
    ) throws {
        try mutateAndPersist { cards in
            guard let index = cards.firstIndex(where: { $0.id == card.id }) else { throw LocalCardStoreError.missingCard }
            guard cards[index].isDeleted else { return }
            guard !card.title.isEmpty else { throw LocalCardStoreError.restoreUnavailable }
            if let deletedAt, cards[index].deletedAt != deletedAt {
                throw LocalCardStoreError.staleRestore
            }
            var restoredCard = card
            restoredCard.deletedAt = nil
            restoredCard = restoredCard.normalizedForLocalSave(by: member, at: date)
            cards[index] = restoredCard
        }
    }

    func exportData() throws -> Data {
        let envelope = CardStoreEnvelope(version: 1, exportedAt: Date(), cards: cards.map(\.redactedDeletionTombstone))
        return try JSONEncoder.fairNest.encode(envelope)
    }

    func deleteAllLocalData() {
        let previousCards = cards
        do {
            try persistAndPublish([])
            try removeCorruptBackups()
            lastLoadErrorMessage = nil
            storeUnavailableDueToLoadFailure = false
        } catch {
            try? persistAndPublish(previousCards)
            assertionFailure(error.localizedDescription)
        }
    }

    func replaceAll(with newCards: [LoadCard]) {
        do {
            try replaceAllThrowing(with: newCards)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    func replaceAllThrowing(with newCards: [LoadCard]) throws {
        try persistAndPublish(newCards)
    }

    func deleteAllLocalDataThrowing() throws {
        let previousCards = cards
        do {
            try persistAndPublish([])
            try removeCorruptBackups()
            lastLoadErrorMessage = nil
            storeUnavailableDueToLoadFailure = false
        } catch {
            try? persistAndPublish(previousCards)
            throw error
        }
    }

    private func sortAndPersist() {
        do {
            try persistAndPublish(cards)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    private func mutateAndPersist(_ mutation: (inout [LoadCard]) throws -> Void) throws {
        var updatedCards = cards
        try mutation(&updatedCards)
        try persistAndPublish(updatedCards)
    }

    private func persist() {
        do {
            try persistAndPublish(cards)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    private func persistAndPublish(_ newCards: [LoadCard]) throws {
        var sortedCards = newCards
        sortedCards.sort { $0.updatedAt > $1.updatedAt }
        try persistThrowing(sortedCards)
        cards = sortedCards
        WidgetSnapshotStore.write(cards: sortedCards)
        WidgetSnapshotStore.reloadTimelines()
    }

    private func persistThrowing(_ cardsToPersist: [LoadCard]) throws {
        guard !storeUnavailableDueToLoadFailure else {
            throw LocalCardStoreError.storeUnavailable
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFailCardPersistence"), !cardsToPersist.isEmpty {
            throw LocalCardStoreError.persistenceFailed
        }
        #endif
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let envelope = CardStoreEnvelope(version: 1, exportedAt: Date(), cards: cardsToPersist)
            let data = try JSONEncoder.fairNest.encode(envelope)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            lastPersistenceErrorMessage = nil
        } catch {
            lastPersistenceErrorMessage = error.localizedDescription
            throw LocalCardStoreError.persistenceFailed
        }
    }

    private func backupCorruptStore() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let backupName = "\(fileURL.lastPathComponent).corrupt.\(Int(Date().timeIntervalSince1970))"
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
        try? fileManager.moveItem(at: fileURL, to: backupURL)
    }

    private func removeCorruptBackups() throws {
        let directory = fileURL.deletingLastPathComponent()
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let backupPrefix = "\(fileURL.lastPathComponent).corrupt."
        for file in files where file.lastPathComponent.hasPrefix(backupPrefix) {
            try fileManager.removeItem(at: file)
        }
    }

    private func removeCorruptBackupsBestEffort() {
        try? removeCorruptBackups()
    }

    private static func sampleCards(now: Date = Date()) -> [LoadCard] {
        let calendar = Calendar.current
        let todayMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrowEvening = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return [
            LoadCard(title: "Set out recycling", type: .recurringResponsibility, owner: .shared, status: .planned, effort: .light, dueDate: todayMorning, recurrence: .weekly(weekday: calendar.component(.weekday, from: todayMorning)), doneCriteria: "Bins are outside."),
            LoadCard(title: "Decide grocery plan", type: .decision, owner: .me, status: .inbox, effort: .medium, dueDate: tomorrowEvening, doneCriteria: "Plan is recorded."),
            LoadCard(title: "Thank partner for handling dishes", type: .appreciation, owner: .partner, status: .done, effort: .tiny, notes: "Small notes count.")
        ]
    }
}
