import Foundation

@MainActor
protocol CheckInStore: AnyObject {
    var records: [CheckInRecord] { get }
    func save(_ record: CheckInRecord)
    func deleteAll()
}

struct CheckInRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var feltHeavy: String
    var gotDone: String
    var needsOwnership: String
    var appreciation: String
    var changes: [OwnershipChange]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        feltHeavy: String,
        gotDone: String,
        needsOwnership: String,
        appreciation: String,
        changes: [OwnershipChange]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.feltHeavy = feltHeavy
        self.gotDone = gotDone
        self.needsOwnership = needsOwnership
        self.appreciation = appreciation
        self.changes = changes
    }
}

struct OwnershipChange: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var owner: CardOwner
    var reason: String

    init(id: UUID = UUID(), title: String, owner: CardOwner, reason: String) {
        self.id = id
        self.title = title
        self.owner = owner
        self.reason = reason
    }
}

@MainActor
final class LocalCheckInStore: ObservableObject, CheckInStore {
    @Published private(set) var records: [CheckInRecord] = []

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("FairNest", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("checkins.json")
        }
        if ProcessInfo.processInfo.arguments.contains("-resetFairNest") {
            try? fileManager.removeItem(at: self.fileURL)
        }
        load()
    }

    func save(_ record: CheckInRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func deleteAll() {
        records = []
        persist()
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder.fairNest.decode([CheckInRecord].self, from: data)
        } catch {
            backupCorruptStore()
            records = []
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.fairNest.encode(records)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            assertionFailure("FairNest check-in store failed to persist: \(error)")
        }
    }

    private func backupCorruptStore() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let backupName = "\(fileURL.lastPathComponent).corrupt.\(Int(Date().timeIntervalSince1970))"
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
        try? fileManager.moveItem(at: fileURL, to: backupURL)
    }
}
