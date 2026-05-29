import Foundation

struct FairNestExportEnvelope: Codable, Equatable {
    var version: Int
    var exportedAt: Date
    var cards: [LoadCard]
    var checkIns: [CheckInRecord]
    var iCloudSyncEnabled: Bool
}

@MainActor
struct PrivacyExportService {
    var cardStore: LocalCardStore
    var checkInStore: LocalCheckInStore

    func exportData() throws -> Data {
        guard !cardStore.isUnavailableDueToLoadFailure else {
            throw PrivacyExportServiceError.cardStoreUnavailable
        }
        guard !checkInStore.isUnavailableDueToLoadFailure else {
            throw PrivacyExportServiceError.checkInStoreUnavailable
        }
        let envelope = FairNestExportEnvelope(
            version: 1,
            exportedAt: Date(),
            cards: cardStore.cards.map(\.redactedDeletionTombstone),
            checkIns: checkInStore.records,
            iCloudSyncEnabled: UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        )
        return try JSONEncoder.fairNest.encode(envelope)
    }

    func exportToTemporaryFile() throws -> URL {
        try Self.removeTemporaryExports()
        let data = try exportData()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FairNest Export-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func deleteAllLocalData() throws {
        let previousCards = cardStore.cards
        let previousCheckIns = checkInStore.records
        do {
            try cardStore.deleteAllLocalDataThrowing()
            try checkInStore.deleteAll()
            try Self.removeTemporaryExports()
        } catch {
            do {
                try cardStore.replaceAllThrowing(with: previousCards)
                try checkInStore.replaceAllThrowing(with: previousCheckIns)
            } catch let rollbackError {
                throw PrivacyExportServiceError.rollbackFailed(original: error, rollback: rollbackError)
            }
            throw error
        }
    }

    static func removeTemporaryExports() throws {
        let directory = FileManager.default.temporaryDirectory
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.lastPathComponent.hasPrefix("FairNest Export-") && file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }
}

enum PrivacyExportServiceError: LocalizedError {
    case cardStoreUnavailable
    case checkInStoreUnavailable
    case rollbackFailed(original: Error, rollback: Error)

    var errorDescription: String? {
        switch self {
        case .cardStoreUnavailable:
            return "FairNest could not read all local cards, so it did not create an incomplete export. Close and reopen FairNest after unlocking this iPhone, then try again."
        case .checkInStoreUnavailable:
            return "FairNest could not read all local check-ins, so it did not create an incomplete export. Close and reopen FairNest after unlocking this iPhone, then try again."
        case let .rollbackFailed(original, rollback):
            return "FairNest could not finish deleting local data (\(original.localizedDescription)) or restore the previous local data (\(rollback.localizedDescription))."
        }
    }
}
