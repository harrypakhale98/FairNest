import CloudKit
import Foundation

enum SyncStatus: Equatable {
    case checking
    case available
    case unavailable
    case notSignedIn
    case restricted
    case permissionDenied
    case offline
    case pending
    case error(String)

    var label: String {
        switch self {
        case .checking: return "Checking iCloud"
        case .available: return "iCloud available"
        case .unavailable: return "iCloud unavailable"
        case .notSignedIn: return "Not signed in to iCloud"
        case .restricted: return "iCloud restricted"
        case .permissionDenied: return "Permission denied"
        case .offline: return "Offline"
        case .pending: return "Sync pending"
        case .error(let message): return message
        }
    }
}

@MainActor
protocol SyncService: AnyObject {
    var status: SyncStatus { get }
    func refreshStatus() async
    func merge(local: [LoadCard], remote: [LoadCard]) -> [LoadCard]
    func upload(cards: [LoadCard]) async throws
    func fetchCards() async throws -> [LoadCard]
    func synchronize(local cards: [LoadCard]) async throws -> [LoadCard]
    func deleteSharedHouseholdData() async throws
    func acceptShare(metadata: CKShare.Metadata) async throws
    func pinCardsToPrivateDatabase(_ cardIDs: Set<UUID>)
}

struct CloudKitHouseholdErasedError: LocalizedError, Equatable {
    var erasedAt: Date

    var errorDescription: String? {
        "This shared household was erased from iCloud. FairNest kept this iPhone from re-uploading old household cards."
    }
}

@MainActor
final class CloudKitSyncService: ObservableObject, SyncService {
    @Published private(set) var status: SyncStatus = .checking

    nonisolated static var containerIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "FairNestCloudKitContainerIdentifier") as? String ?? "iCloud.com.hardikpakhale.fairnest"
    }

    private let containerProvider: () -> CKContainer
    private var recordLocations: [UUID: CloudKitRecordLocation] = [:]
    private var preferredSharedZoneID: CKRecordZone.ID?

    init(containerProvider: @escaping () -> CKContainer = { CKContainer(identifier: CloudKitSyncService.containerIdentifier) }) {
        self.containerProvider = containerProvider
    }

    func refreshStatus() async {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.arguments.contains("-disableCloudKit") {
            status = .unavailable
            return
        }
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["FAIRNEST_ENABLE_CLOUDKIT"] == "1" else {
            status = .unavailable
            return
        }
        #endif
        status = .checking
        do {
            let container = containerProvider()
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                status = .available
            case .noAccount:
                status = .notSignedIn
            case .restricted:
                status = .restricted
            case .couldNotDetermine:
                status = .unavailable
            case .temporarilyUnavailable:
                status = .offline
            @unknown default:
                status = .unavailable
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func merge(local: [LoadCard], remote: [LoadCard]) -> [LoadCard] {
        ConflictResolver.merge(local: local, remote: remote)
    }

    func upload(cards: [LoadCard]) async throws {
        try ensureCloudKitEnabledForRuntime()
        let container = containerProvider()
        let privateDatabase = container.privateCloudDatabase
        let sharedDatabase = container.sharedCloudDatabase
        preferredSharedZoneID = preferredSharedZoneID ?? CloudKitHouseholdSelection.selectedSharedZoneID()
        let privateZoneID = CloudKitCardMapper.zoneID()
        try await ensureHouseholdZone(in: privateDatabase)
        try await throwIfHouseholdWasErased(in: privateDatabase, zoneID: privateZoneID, clearsSharedSelection: false)
        if let preferredSharedZoneID {
            try await throwIfHouseholdWasErased(in: sharedDatabase, zoneID: preferredSharedZoneID, clearsSharedSelection: true)
        }

        var privateRecords: [CKRecord] = []
        var sharedRecordsByZone: [(zoneID: CKRecordZone.ID, records: [CKRecord])] = []

        func appendSharedRecord(_ record: CKRecord, zoneID: CKRecordZone.ID) {
            if let index = sharedRecordsByZone.firstIndex(where: { $0.zoneID == zoneID }) {
                sharedRecordsByZone[index].records.append(record)
            } else {
                sharedRecordsByZone.append((zoneID, [record]))
            }
        }

        for card in cards where !CloudKitCardMapper.isHouseholdErasureMarker(card.id) {
            switch recordLocations[card.id]?.scope {
            case .sharedDatabase:
                let zoneID = recordLocations[card.id]?.zoneID ?? CloudKitCardMapper.zoneID()
                appendSharedRecord(try CloudKitCardMapper.record(from: card, zoneID: zoneID), zoneID: zoneID)
            case .privateDatabase:
                let zoneID = recordLocations[card.id]?.zoneID ?? CloudKitCardMapper.zoneID()
                privateRecords.append(try CloudKitCardMapper.record(from: card, zoneID: zoneID))
            case nil:
                if let sharedZoneID = preferredSharedZoneID {
                    appendSharedRecord(try CloudKitCardMapper.record(from: card, zoneID: sharedZoneID), zoneID: sharedZoneID)
                } else {
                    privateRecords.append(try CloudKitCardMapper.record(from: card))
                }
            }
        }

        try await save(privateRecords, in: privateDatabase, scope: .privateDatabase)
        for group in sharedRecordsByZone {
            try await save(group.records, in: sharedDatabase, scope: .sharedDatabase)
        }
        status = .available
    }

    func fetchCards() async throws -> [LoadCard] {
        try ensureCloudKitEnabledForRuntime()
        let container = containerProvider()
        let privateCards = try await fetchPrivateCards(in: container.privateCloudDatabase)
        let sharedCards = try await fetchSharedCards(in: container.sharedCloudDatabase)
        status = .available
        return privateCards + sharedCards
    }

    func synchronize(local cards: [LoadCard]) async throws -> [LoadCard] {
        try ensureCloudKitEnabledForRuntime()
        let remoteCards = try await fetchCards()
        let merged = merge(local: cards, remote: remoteCards)
        try await upload(cards: merged)
        return merged
    }

    func pinCardsToPrivateDatabase(_ cardIDs: Set<UUID>) {
        let zoneID = CloudKitCardMapper.zoneID()
        for cardID in cardIDs where recordLocations[cardID] == nil {
            recordLocations[cardID] = CloudKitRecordLocation(scope: .privateDatabase, zoneID: zoneID)
        }
    }

    func deleteSharedHouseholdData() async throws {
        try ensureCloudKitEnabledForRuntime()
        let container = containerProvider()
        let privateDatabase = container.privateCloudDatabase
        let sharedDatabase = container.sharedCloudDatabase
        let erasedAt = Date()
        var deletionProgress = CloudKitHouseholdDeletionProgress()

        do {
            let privateZoneID = CloudKitCardMapper.zoneID()
            try await ensureHouseholdZone(in: privateDatabase)
            try await deleteCardRecords(in: privateDatabase, zoneID: privateZoneID)
            try await saveHouseholdErasureMarker(in: privateDatabase, zoneID: privateZoneID, erasedAt: erasedAt)
            deletionProgress.markDeletedData()
        } catch let error as CKError where error.code == .zoneNotFound {
            // Nothing private exists for this account.
        } catch let error as CKError where error.code == .notAuthenticated || error.code == .permissionFailure {
            deletionProgress.recordPermissionFailure(error)
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }

        do {
            if let zoneID = try await activeSharedHouseholdZoneID(in: sharedDatabase) {
                try await deleteCardRecords(in: sharedDatabase, zoneID: zoneID)
                try await saveHouseholdErasureMarker(in: sharedDatabase, zoneID: zoneID, erasedAt: erasedAt)
                deletionProgress.markDeletedData()
            }
        } catch let error as CKError where error.code == .notAuthenticated || error.code == .permissionFailure {
            deletionProgress.recordPermissionFailure(error)
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }

        do {
            try deletionProgress.throwPermissionFailureIfPresent()
        } catch {
            status = .permissionDenied
            throw error
        }

        CloudKitHouseholdErasureState.acknowledge(erasedAt)
        forgetSharedHouseholdSelection()
        status = .available
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        try ensureCloudKitEnabledForRuntime()
        let results = try await containerProvider().accept([metadata])
        for result in results.values {
            switch result {
            case .success(let share):
                CloudKitHouseholdSelection.rememberSharedZoneID(share.recordID.zoneID)
                preferredSharedZoneID = share.recordID.zoneID
                status = .available
            case .failure(let error):
                status = .error(error.localizedDescription)
                throw error
            }
        }
    }

    func ensureHouseholdZone(in database: CKDatabase) async throws {
        let zoneID = CloudKitCardMapper.zoneID()
        do {
            _ = try await database.recordZone(for: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        }
    }

    private func householdZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        let zones = try await database.allRecordZones()
        return zones
            .map(\.zoneID)
            .filter { $0.zoneName == CloudKitCardMapper.zoneName }
    }

    private func activeSharedHouseholdZoneID(in database: CKDatabase) async throws -> CKRecordZone.ID? {
        let zoneID = CloudKitHouseholdSelection.selectedSharedZoneID(from: try await householdZoneIDs(in: database))
        preferredSharedZoneID = zoneID
        return zoneID
    }

    private func deleteCardRecords(in database: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let query = CKQuery(recordType: CloudKitCardMapper.recordType, predicate: NSPredicate(value: true))
        var recordIDs: [CKRecord.ID] = []
        let firstPage = try await database.records(matching: query, inZoneWith: zoneID)
        try appendRecordIDs(from: firstPage.matchResults, to: &recordIDs)
        var cursor = firstPage.queryCursor
        while let nextCursor = cursor {
            let page = try await database.records(continuingMatchFrom: nextCursor)
            try appendRecordIDs(from: page.matchResults, to: &recordIDs)
            cursor = page.queryCursor
        }
        try await deleteRecordIDs(recordIDs, in: database)
    }

    private func appendRecordIDs(
        from results: [(CKRecord.ID, Result<CKRecord, any Error>)],
        to recordIDs: inout [CKRecord.ID]
    ) throws {
        for (recordID, result) in results {
            _ = try result.get()
            guard !CloudKitCardMapper.isHouseholdErasureMarker(recordID) else { continue }
            recordIDs.append(recordID)
        }
    }

    private func deleteRecordIDs(_ recordIDs: [CKRecord.ID], in database: CKDatabase) async throws {
        guard !recordIDs.isEmpty else { return }
        let batchSize = 200
        var startIndex = recordIDs.startIndex
        while startIndex < recordIDs.endIndex {
            let endIndex = recordIDs.index(startIndex, offsetBy: batchSize, limitedBy: recordIDs.endIndex) ?? recordIDs.endIndex
            let batch = Array(recordIDs[startIndex..<endIndex])
            let result = try await database.modifyRecords(
                saving: [],
                deleting: batch,
                savePolicy: .changedKeys,
                atomically: true
            )
            try CloudKitRecordOperationValidator.validateDeleteResults(
                result.deleteResults,
                expectedRecordIDs: batch
            )
            startIndex = endIndex
        }
    }

    private func fetchPrivateCards(in database: CKDatabase) async throws -> [LoadCard] {
        let zoneID = CloudKitCardMapper.zoneID()
        try await ensureHouseholdZone(in: database)
        try await throwIfHouseholdWasErased(in: database, zoneID: zoneID, clearsSharedSelection: false)
        return try await fetchCards(in: database, zoneID: zoneID, scope: .privateDatabase)
    }

    private func fetchSharedCards(in database: CKDatabase) async throws -> [LoadCard] {
        do {
            guard let zoneID = try await activeSharedHouseholdZoneID(in: database) else {
                return []
            }
            try await throwIfHouseholdWasErased(in: database, zoneID: zoneID, clearsSharedSelection: true)
            return try await fetchCards(in: database, zoneID: zoneID, scope: .sharedDatabase)
        } catch let error as CloudKitHouseholdErasedError {
            throw error
        } catch let error as CKError where error.code == .notAuthenticated || error.code == .permissionFailure {
            forgetSharedHouseholdSelection()
            return []
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            forgetSharedHouseholdSelection()
            return []
        }
    }

    private func fetchCards(in database: CKDatabase, zoneID: CKRecordZone.ID, scope: CloudKitDatabaseScope) async throws -> [LoadCard] {
        let query = CKQuery(recordType: CloudKitCardMapper.recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        let firstPage = try await database.records(matching: query, inZoneWith: zoneID)
        records.append(contentsOf: try firstPage.matchResults.compactMap { try $0.1.get() })
        var cursor = firstPage.queryCursor
        while let nextCursor = cursor {
            let page = try await database.records(continuingMatchFrom: nextCursor)
            records.append(contentsOf: try page.matchResults.compactMap { try $0.1.get() })
            cursor = page.queryCursor
        }
        var cards: [LoadCard] = []
        for record in records {
            guard !CloudKitCardMapper.isHouseholdErasureMarker(record.recordID) else { continue }
            let card = try CloudKitCardMapper.card(from: record)
            recordLocations[card.id] = CloudKitRecordLocation(scope: scope, zoneID: record.recordID.zoneID)
            cards.append(card)
        }
        return cards
    }

    private func throwIfHouseholdWasErased(
        in database: CKDatabase,
        zoneID: CKRecordZone.ID,
        clearsSharedSelection: Bool
    ) async throws {
        guard let erasedAt = try await householdErasureDate(in: database, zoneID: zoneID),
              CloudKitHouseholdErasureState.requiresAcknowledgement(erasedAt) else {
            return
        }
        if clearsSharedSelection {
            forgetSharedHouseholdSelection()
        }
        status = .pending
        throw CloudKitHouseholdErasedError(erasedAt: erasedAt)
    }

    private func householdErasureDate(in database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> Date? {
        let recordID = CloudKitCardMapper.householdErasureMarkerRecordID(zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            return CloudKitCardMapper.householdErasureDate(from: record)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    private func saveHouseholdErasureMarker(
        in database: CKDatabase,
        zoneID: CKRecordZone.ID,
        erasedAt: Date
    ) async throws {
        let record = try CloudKitCardMapper.householdErasureMarkerRecord(erasedAt: erasedAt, zoneID: zoneID)
        _ = try await database.save(record)
    }

    private func save(_ records: [CKRecord], in database: CKDatabase, scope: CloudKitDatabaseScope) async throws {
        guard !records.isEmpty else { return }
        let result = try await database.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
        let savedRecords = try CloudKitRecordOperationValidator.savedRecords(
            from: result.saveResults,
            expectedRecordIDs: records.map(\.recordID)
        )
        for record in savedRecords {
            if let id = UUID(uuidString: record.recordID.recordName) {
                recordLocations[id] = CloudKitRecordLocation(scope: scope, zoneID: record.recordID.zoneID)
            }
        }
    }

    private func forgetSharedHouseholdSelection() {
        preferredSharedZoneID = nil
        CloudKitHouseholdSelection.clearSelectedSharedZone()
        recordLocations = recordLocations.filter { _, location in
            location.scope != .sharedDatabase
        }
    }

    func isPinnedToPrivateDatabaseForTesting(_ cardID: UUID) -> Bool {
        recordLocations[cardID]?.scope == .privateDatabase
    }

    private func ensureCloudKitEnabledForRuntime() throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["FAIRNEST_ENABLE_CLOUDKIT"] == "1" else {
            throw CloudKitRuntimeError.disabledInSimulator
        }
        #endif
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.arguments.contains("-disableCloudKit") {
            throw CloudKitRuntimeError.disabledForTesting
        }
    }
}

enum CloudKitHouseholdErasureState {
    static let acknowledgedErasedAtKey = "acknowledgedCloudKitHouseholdErasedAt"

    static func requiresAcknowledgement(_ erasedAt: Date, defaults: UserDefaults = .standard) -> Bool {
        guard let acknowledgedAt = defaults.object(forKey: acknowledgedErasedAtKey) as? Date else {
            return true
        }
        return erasedAt > acknowledgedAt
    }

    static func acknowledge(_ erasedAt: Date, defaults: UserDefaults = .standard) {
        if let acknowledgedAt = defaults.object(forKey: acknowledgedErasedAtKey) as? Date,
           erasedAt <= acknowledgedAt {
            return
        }
        defaults.set(erasedAt, forKey: acknowledgedErasedAtKey)
    }
}

private enum CloudKitDatabaseScope {
    case privateDatabase
    case sharedDatabase
}

private struct CloudKitRecordLocation {
    var scope: CloudKitDatabaseScope
    var zoneID: CKRecordZone.ID
}

struct CloudKitHouseholdDeletionProgress {
    private(set) var deletedData = false
    private var permissionFailure: Error?

    mutating func markDeletedData() {
        deletedData = true
    }

    mutating func recordPermissionFailure(_ error: Error) {
        permissionFailure = error
    }

    func throwPermissionFailureIfPresent() throws {
        if let permissionFailure {
            throw permissionFailure
        }
    }
}

enum CloudKitRecordOperationValidator {
    static func savedRecords(
        from results: [CKRecord.ID: Result<CKRecord, any Error>],
        expectedRecordIDs: [CKRecord.ID]
    ) throws -> [CKRecord] {
        var records: [CKRecord] = []
        var failures: [String] = missingResultMessages(expectedRecordIDs: expectedRecordIDs, actualRecordIDs: Set(results.keys))

        for recordID in expectedRecordIDs {
            guard let result = results[recordID] else { continue }
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                failures.append("\(recordID.recordName): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            throw CloudKitPartialResultError(operation: "save", failures: failures)
        }
        return records
    }

    static func validateDeleteResults(
        _ results: [CKRecord.ID: Result<Void, any Error>],
        expectedRecordIDs: [CKRecord.ID]
    ) throws {
        var failures = missingResultMessages(expectedRecordIDs: expectedRecordIDs, actualRecordIDs: Set(results.keys))

        for recordID in expectedRecordIDs {
            guard let result = results[recordID] else { continue }
            if case .failure(let error) = result {
                failures.append("\(recordID.recordName): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            throw CloudKitPartialResultError(operation: "delete", failures: failures)
        }
    }

    private static func missingResultMessages(
        expectedRecordIDs: [CKRecord.ID],
        actualRecordIDs: Set<CKRecord.ID>
    ) -> [String] {
        expectedRecordIDs
            .filter { !actualRecordIDs.contains($0) }
            .map { "\($0.recordName): missing CloudKit result" }
    }
}

struct CloudKitPartialResultError: LocalizedError, Equatable {
    var operation: String
    var failures: [String]

    var errorDescription: String? {
        let sample = failures.prefix(3).joined(separator: "; ")
        return "CloudKit \(operation) failed for \(failures.count) record(s): \(sample)"
    }
}

enum CloudKitRuntimeError: LocalizedError, Equatable {
    case disabledInSimulator
    case disabledForTesting

    var errorDescription: String? {
        switch self {
        case .disabledInSimulator:
            return "CloudKit is disabled in this simulator run."
        case .disabledForTesting:
            return "CloudKit is disabled for this test run."
        }
    }
}

enum ConflictResolver {
    static func merge(local: [LoadCard], remote: [LoadCard]) -> [LoadCard] {
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for remoteCard in remote {
            if let localCard = merged[remoteCard.id] {
                merged[remoteCard.id] = resolve(local: localCard, remote: remoteCard)
            } else {
                merged[remoteCard.id] = remoteCard
            }
        }
        return merged.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func resolve(local: LoadCard, remote: LoadCard) -> LoadCard {
        if local.isDeleted, !remote.isDeleted { return local }
        if remote.isDeleted, !local.isDeleted { return remote }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        return local
    }
}
