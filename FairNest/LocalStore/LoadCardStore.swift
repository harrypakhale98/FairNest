import Foundation

@MainActor
protocol LoadCardStore: AnyObject {
    var cards: [LoadCard] { get }
    var activeCards: [LoadCard] { get }

    func load()
    func upsert(_ card: LoadCard)
    func add(_ suggestion: BrainDumpSuggestion) -> LoadCard
    func transition(id: UUID, to status: CardStatus) throws
    func reassign(id: UUID, to owner: CardOwner)
    func snooze(id: UUID, days: Int)
    func delete(id: UUID)
    func restore(id: UUID)
    func exportData() throws -> Data
    func deleteAllLocalData()
}

struct CardStoreEnvelope: Codable, Equatable {
    var version: Int
    var exportedAt: Date
    var cards: [LoadCard]
}

@MainActor
final class LocalCardStore: ObservableObject, LoadCardStore {
    @Published private(set) var cards: [LoadCard] = []

    private let fileURL: URL
    private let fileManager: FileManager

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
        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder.fairNest.decode(CardStoreEnvelope.self, from: data)
            cards = envelope.cards.sorted { $0.updatedAt > $1.updatedAt }
            WidgetSnapshotStore.write(cards: cards)
        } catch {
            backupCorruptStore()
            cards = []
        }
    }

    func upsert(_ card: LoadCard) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        } else {
            cards.insert(card, at: 0)
        }
        sortAndPersist()
    }

    @discardableResult
    func add(_ suggestion: BrainDumpSuggestion) -> LoadCard {
        let card = suggestion.makeCard()
        upsert(card)
        return card
    }

    func transition(id: UUID, to status: CardStatus) throws {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        var card = cards[index]
        try card.transition(to: status)
        cards[index] = card
        sortAndPersist()
    }

    func reassign(id: UUID, to owner: CardOwner) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].reassign(to: owner)
        sortAndPersist()
    }

    func snooze(id: UUID, days: Int) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].snooze(days: days)
        sortAndPersist()
    }

    func delete(id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].softDelete()
        sortAndPersist()
    }

    func restore(id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].restore()
        sortAndPersist()
    }

    func exportData() throws -> Data {
        let envelope = CardStoreEnvelope(version: 1, exportedAt: Date(), cards: cards)
        return try JSONEncoder.fairNest.encode(envelope)
    }

    func deleteAllLocalData() {
        cards = []
        persist()
    }

    func replaceAll(with newCards: [LoadCard]) {
        cards = newCards
        sortAndPersist()
    }

    private func sortAndPersist() {
        cards.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let envelope = CardStoreEnvelope(version: 1, exportedAt: Date(), cards: cards)
            let data = try JSONEncoder.fairNest.encode(envelope)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            WidgetSnapshotStore.write(cards: cards)
            WidgetSnapshotStore.reloadTimelines()
        } catch {
            assertionFailure("FairNest local store failed to persist: \(error)")
        }
    }

    private func backupCorruptStore() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let backupName = "\(fileURL.lastPathComponent).corrupt.\(Int(Date().timeIntervalSince1970))"
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
        try? fileManager.moveItem(at: fileURL, to: backupURL)
    }

    private static func sampleCards(now: Date = Date()) -> [LoadCard] {
        [
            LoadCard(title: "Set out recycling", type: .recurringResponsibility, owner: .shared, status: .planned, effort: .light, dueDate: now, recurrence: .weekly(weekday: Calendar.current.component(.weekday, from: now)), doneCriteria: "Bins are outside."),
            LoadCard(title: "Decide grocery plan", type: .decision, owner: .me, status: .inbox, effort: .medium, dueDate: Calendar.current.date(byAdding: .day, value: 1, to: now), doneCriteria: "Plan is recorded."),
            LoadCard(title: "Thank partner for handling dishes", type: .appreciation, owner: .partner, status: .done, effort: .tiny, notes: "Small notes count.")
        ]
    }
}
