import Foundation

@MainActor
protocol CheckInStore: AnyObject {
    var records: [CheckInRecord] { get }
    func save(_ record: CheckInRecord) throws
    func replaceAllThrowing(with records: [CheckInRecord]) throws
    func deleteAll() throws
}

enum LocalCheckInStoreError: LocalizedError {
    case persistenceFailed
    case storeUnavailable

    var errorDescription: String? {
        switch self {
        case .persistenceFailed:
            return "FairNest could not save check-in data. Try again before closing the app."
        case .storeUnavailable:
            return "FairNest could not read the local check-in store. Close and reopen FairNest after unlocking this iPhone, then try again."
        }
    }
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
    @Published private(set) var lastLoadErrorMessage: String?
    @Published private(set) var lastPersistenceErrorMessage: String?

    private let fileURL: URL
    private let fileManager: FileManager
    private var storeUnavailableDueToLoadFailure = false

    var isUnavailableDueToLoadFailure: Bool {
        storeUnavailableDueToLoadFailure
    }

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
            removeCorruptBackupsBestEffort()
        }
        load()
    }

    func save(_ record: CheckInRecord) throws {
        var updatedRecords = records
        updatedRecords.insert(record, at: 0)
        try persistAndPublish(updatedRecords)
    }

    func deleteAll() throws {
        let previousRecords = records
        do {
            try persistAndPublish([])
            try removeCorruptBackups()
            lastLoadErrorMessage = nil
            storeUnavailableDueToLoadFailure = false
        } catch {
            try? persistAndPublish(previousRecords)
            throw error
        }
    }

    func replaceAllThrowing(with newRecords: [CheckInRecord]) throws {
        try persistAndPublish(newRecords)
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            lastLoadErrorMessage = error.localizedDescription
            storeUnavailableDueToLoadFailure = true
            return
        }

        do {
            records = try JSONDecoder.fairNest.decode([CheckInRecord].self, from: data)
            lastLoadErrorMessage = nil
            storeUnavailableDueToLoadFailure = false
        } catch is DecodingError {
            backupCorruptStore()
            records = []
            lastLoadErrorMessage = "FairNest found an unreadable local check-in store and moved it aside."
            storeUnavailableDueToLoadFailure = false
        } catch {
            lastLoadErrorMessage = error.localizedDescription
            storeUnavailableDueToLoadFailure = true
        }
    }

    private func persistAndPublish(_ newRecords: [CheckInRecord]) throws {
        try persistThrowing(newRecords)
        records = newRecords
    }

    private func persistThrowing(_ recordsToPersist: [CheckInRecord]) throws {
        guard !storeUnavailableDueToLoadFailure else {
            throw LocalCheckInStoreError.storeUnavailable
        }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.fairNest.encode(recordsToPersist)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            lastPersistenceErrorMessage = nil
        } catch {
            lastPersistenceErrorMessage = error.localizedDescription
            throw LocalCheckInStoreError.persistenceFailed
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
}
