import CloudKit
import XCTest
@testable import FairNest

final class SyncAndCloudKitTests: XCTestCase {
    func testConflictResolutionUsesLatestUpdatedAt() {
        let id = UUID()
        let older = LoadCard(id: id, title: "Older", updatedAt: Date(timeIntervalSince1970: 10))
        let newer = LoadCard(id: id, title: "Newer", updatedAt: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(ConflictResolver.resolve(local: older, remote: newer).title, "Newer")
        XCTAssertEqual(ConflictResolver.resolve(local: newer, remote: older).title, "Newer")
    }

    func testCloudKitMappingRoundTripsCardFields() throws {
        let card = LoadCard(
            id: UUID(),
            title: "Pay utilities",
            type: .reminder,
            owner: .me,
            status: .planned,
            effort: .light,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            recurrence: .monthly(day: 14),
            notes: "Use household account",
            doneCriteria: "Bill paid",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let record = try CloudKitCardMapper.record(from: card)
        let mapped = try CloudKitCardMapper.card(from: record)

        XCTAssertEqual(mapped.id, card.id)
        XCTAssertEqual(mapped.title, card.title)
        XCTAssertEqual(mapped.type, .reminder)
        XCTAssertEqual(mapped.recurrence, .monthly(day: 14))
    }

    func testCloudKitCardsUseHouseholdZone() throws {
        let card = LoadCard(id: UUID(), title: "Rotate laundry")
        let record = try CloudKitCardMapper.record(from: card)

        XCTAssertEqual(record.recordID.zoneID.zoneName, CloudKitCardMapper.zoneName)
        XCTAssertEqual(record.recordID.recordName, card.id.uuidString)
    }

    @MainActor
    func testAcceptedSharePinsExistingLocalCardsToPrivateDatabase() async {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousPins = UserDefaults.standard.object(forKey: "acceptedSharePrivateCardIDs")
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
            if let previousPins {
                UserDefaults.standard.set(previousPins, forKey: "acceptedSharePrivateCardIDs")
            } else {
                UserDefaults.standard.removeObject(forKey: "acceptedSharePrivateCardIDs")
            }
        }
        UserDefaults.standard.removeObject(forKey: "acceptedSharePrivateCardIDs")
        let cardStore = LocalCardStore(fileURL: tempURL())
        let localCard = cardStore.add(BrainDumpSuggestion(title: "Local only", type: .task))
        let services = AppServices(cardStore: cardStore, checkInStore: LocalCheckInStore(fileURL: tempURL()))

        await services.handleAcceptedCloudKitShare()

        XCTAssertTrue(services.syncService.isPinnedToPrivateDatabaseForTesting(localCard.id))
        XCTAssertTrue(UserDefaults.standard.stringArray(forKey: "acceptedSharePrivateCardIDs")?.contains(localCard.id.uuidString) == true)
    }

    func testCloudKitSaveResultValidatorThrowsOnPartialFailure() throws {
        let successID = CKRecord.ID(recordName: UUID().uuidString, zoneID: CloudKitCardMapper.zoneID())
        let failedID = CKRecord.ID(recordName: UUID().uuidString, zoneID: CloudKitCardMapper.zoneID())
        let successRecord = CKRecord(recordType: CloudKitCardMapper.recordType, recordID: successID)
        let results: [CKRecord.ID: Result<CKRecord, any Error>] = [
            successID: .success(successRecord),
            failedID: .failure(TestCloudKitPartialFailure())
        ]

        XCTAssertThrowsError(try CloudKitRecordOperationValidator.savedRecords(
            from: results,
            expectedRecordIDs: [successID, failedID]
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("CloudKit save failed"))
            XCTAssertTrue(error.localizedDescription.contains(failedID.recordName))
        }
    }

    func testCloudKitDeleteResultValidatorThrowsOnMissingResult() throws {
        let deletedID = CKRecord.ID(recordName: UUID().uuidString, zoneID: CloudKitCardMapper.zoneID())
        let missingID = CKRecord.ID(recordName: UUID().uuidString, zoneID: CloudKitCardMapper.zoneID())

        XCTAssertThrowsError(try CloudKitRecordOperationValidator.validateDeleteResults(
            [deletedID: .success(())],
            expectedRecordIDs: [deletedID, missingID]
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("CloudKit delete failed"))
            XCTAssertTrue(error.localizedDescription.contains(missingID.recordName))
        }
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}

private struct TestCloudKitPartialFailure: LocalizedError {
    var errorDescription: String? {
        "Simulated partial failure"
    }
}
