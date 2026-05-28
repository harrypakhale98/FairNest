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
        let envelope = FairNestExportEnvelope(
            version: 1,
            exportedAt: Date(),
            cards: cardStore.cards,
            checkIns: checkInStore.records,
            iCloudSyncEnabled: UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        )
        return try JSONEncoder.fairNest.encode(envelope)
    }

    func exportToTemporaryFile() throws -> URL {
        Self.removeTemporaryExports()
        let data = try exportData()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FairNest Export-\(Int(Date().timeIntervalSince1970))")
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
            Self.removeTemporaryExports()
        } catch {
            try? cardStore.replaceAllThrowing(with: previousCards)
            try? checkInStore.replaceAllThrowing(with: previousCheckIns)
            throw error
        }
    }

    static func removeTemporaryExports() {
        let directory = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("FairNest Export-") && file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
