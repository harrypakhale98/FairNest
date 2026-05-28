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
        try await ensureHouseholdZone(in: privateDatabase)

        var privateRecords: [CKRecord] = []
        var sharedRecordsByZone: [(zoneID: CKRecordZone.ID, records: [CKRecord])] = []

        func appendSharedRecord(_ record: CKRecord, zoneID: CKRecordZone.ID) {
            if let index = sharedRecordsByZone.firstIndex(where: { $0.zoneID == zoneID }) {
                sharedRecordsByZone[index].records.append(record)
            } else {
                sharedRecordsByZone.append((zoneID, [record]))
            }
        }

        for card in cards {
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
        var deletedData = false
        var permissionFailure: Error?

        do {
            try await deletePrivateHouseholdZone(in: privateDatabase)
            deletedData = true
        } catch let error as CKError where error.code == .zoneNotFound {
            // Nothing private exists for this account.
        } catch let error as CKError where error.code == .notAuthenticated || error.code == .permissionFailure {
            permissionFailure = error
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }

        do {
            let sharedZoneIDs = try await householdZoneIDs(in: sharedDatabase)
            for zoneID in sharedZoneIDs {
                try await deleteCardRecords(in: sharedDatabase, zoneID: zoneID)
                deletedData = true
            }
        } catch let error as CKError where error.code == .notAuthenticated || error.code == .permissionFailure {
            permissionFailure = error
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }

        if let permissionFailure, !deletedData {
            status = .permissionDenied
            throw permissionFailure
        }

        preferredSharedZoneID = nil
        status = .available
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        try ensureCloudKitEnabledForRuntime()
        let results = try await containerProvider().accept([metadata])
        for result in results.values {
            switch result {
            case .success:
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

    private func deletePrivateHouseholdZone(in database: CKDatabase) async throws {
        let zoneID = CloudKitCardMapper.zoneID()
        _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
    }

    private func householdZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        let zones = try await database.allRecordZones()
        return zones
            .map(\.zoneID)
            .filter { $0.zoneName == CloudKitCardMapper.zoneName }
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
        try await ensureHouseholdZone(in: database)
        return try await fetchCards(in: database, zoneID: CloudKitCardMapper.zoneID(), scope: .privateDatabase)
    }

    private func fetchSharedCards(in database: CKDatabase) async throws -> [LoadCard] {
        do {
            let zones = try await database.allRecordZones()
            let householdZones = zones.filter { $0.zoneID.zoneName == CloudKitCardMapper.zoneName }
            preferredSharedZoneID = householdZones.first?.zoneID
            var cards: [LoadCard] = []
            for zone in householdZones {
                cards.append(contentsOf: try await fetchCards(in: database, zoneID: zone.zoneID, scope: .sharedDatabase))
            }
            return cards
        } catch let error as CKError where error.code == .notAuthenticated || error.code == .permissionFailure {
            preferredSharedZoneID = nil
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
            let card = try CloudKitCardMapper.card(from: record)
            recordLocations[card.id] = CloudKitRecordLocation(scope: scope, zoneID: record.recordID.zoneID)
            cards.append(card)
        }
        return cards
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

private enum CloudKitDatabaseScope {
    case privateDatabase
    case sharedDatabase
}

private struct CloudKitRecordLocation {
    var scope: CloudKitDatabaseScope
    var zoneID: CKRecordZone.ID
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
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        if remote.deletedAt != nil, local.deletedAt == nil { return remote }
        return local
    }
}
