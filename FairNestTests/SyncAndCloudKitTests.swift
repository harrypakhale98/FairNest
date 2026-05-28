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
}
