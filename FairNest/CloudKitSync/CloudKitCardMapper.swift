import CloudKit
import Foundation

enum CloudKitCardMapper {
    static let recordType = "LoadCard"
    static let zoneName = "FairNestHousehold"
    static let householdErasureMarkerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func zoneID(ownerName: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    static func recordID(for card: LoadCard, ownerName: String = CKCurrentUserDefaultName) -> CKRecord.ID {
        CKRecord.ID(recordName: card.id.uuidString, zoneID: zoneID(ownerName: ownerName))
    }

    static func recordID(for card: LoadCard, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: card.id.uuidString, zoneID: zoneID)
    }

    static func isHouseholdErasureMarker(_ id: UUID) -> Bool {
        id == householdErasureMarkerID
    }

    static func isHouseholdErasureMarker(_ recordID: CKRecord.ID) -> Bool {
        recordID.recordName == householdErasureMarkerID.uuidString
    }

    static func householdErasureMarkerRecordID(zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: householdErasureMarkerID.uuidString, zoneID: zoneID)
    }

    static func householdErasureMarkerRecord(erasedAt: Date, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let marker = LoadCard(
            id: householdErasureMarkerID,
            title: "",
            type: .task,
            owner: .shared,
            status: .done,
            effort: .tiny,
            dueDate: nil,
            recurrence: .none,
            notes: "",
            doneCriteria: "",
            createdBy: .system,
            createdAt: erasedAt,
            modifiedBy: .system,
            updatedAt: erasedAt,
            deletedAt: erasedAt
        )
        return try record(from: marker, zoneID: zoneID)
    }

    static func householdErasureDate(from record: CKRecord) -> Date? {
        guard isHouseholdErasureMarker(record.recordID) else { return nil }
        return record["deletedAt"] as? Date ?? record["updatedAt"] as? Date
    }

    static func record(from card: LoadCard, ownerName: String = CKCurrentUserDefaultName) throws -> CKRecord {
        try record(from: card, zoneID: zoneID(ownerName: ownerName))
    }

    static func record(from card: LoadCard, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let mappedCard = card.redactedDeletionTombstone
        let record = CKRecord(recordType: recordType, recordID: recordID(for: mappedCard, zoneID: zoneID))
        try apply(mappedCard, to: record)
        return record
    }

    static func apply(_ card: LoadCard, to record: CKRecord) throws {
        let mappedCard = card.redactedDeletionTombstone
        set(mappedCard.title, forKey: "title", on: record)
        set(mappedCard.type.rawValue, forKey: "type", on: record)
        set(mappedCard.owner.rawValue, forKey: "owner", on: record)
        set(mappedCard.status.rawValue, forKey: "status", on: record)
        set(mappedCard.effort.rawValue, forKey: "effort", on: record)
        set(mappedCard.notes, forKey: "notes", on: record)
        set(mappedCard.doneCriteria, forKey: "doneCriteria", on: record)
        set(mappedCard.createdBy.rawValue, forKey: "createdBy", on: record)
        set(mappedCard.modifiedBy.rawValue, forKey: "modifiedBy", on: record)
        set(mappedCard.createdAt, forKey: "createdAt", on: record)
        set(mappedCard.updatedAt, forKey: "updatedAt", on: record)
        set(mappedCard.dueDate, forKey: "dueDate", on: record)
        set(mappedCard.deletedAt, forKey: "deletedAt", on: record)
        let recurrenceData = try JSONEncoder.fairNest.encode(mappedCard.recurrence)
        set(String(decoding: recurrenceData, as: UTF8.self), forKey: "recurrence", on: record)
    }

    static func card(from record: CKRecord) throws -> LoadCard {
        guard
            let uuid = UUID(uuidString: record.recordID.recordName),
            let title = record["title"] as? String,
            let typeRaw = record["type"] as? String,
            let ownerRaw = record["owner"] as? String,
            let statusRaw = record["status"] as? String,
            let effortRaw = record["effort"] as? Int,
            let createdByRaw = record["createdBy"] as? String,
            let modifiedByRaw = record["modifiedBy"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitMappingError.missingRequiredField
        }

        let recurrence: Recurrence
        if let recurrenceString = record["recurrence"] as? String,
           let recurrenceData = recurrenceString.data(using: .utf8) {
            recurrence = try JSONDecoder.fairNest.decode(Recurrence.self, from: recurrenceData)
        } else {
            recurrence = .none
        }

        return LoadCard(
            id: uuid,
            title: title,
            type: CardType(rawValue: typeRaw) ?? .task,
            owner: CardOwner(rawValue: ownerRaw) ?? .unassigned,
            status: CardStatus(rawValue: statusRaw) ?? .inbox,
            effort: Effort(rawValue: effortRaw) ?? .medium,
            dueDate: record["dueDate"] as? Date,
            recurrence: recurrence,
            notes: record["notes"] as? String ?? "",
            doneCriteria: record["doneCriteria"] as? String ?? "",
            createdBy: HouseholdMember(rawValue: createdByRaw) ?? .me,
            createdAt: createdAt,
            modifiedBy: HouseholdMember(rawValue: modifiedByRaw) ?? .me,
            updatedAt: updatedAt,
            deletedAt: record["deletedAt"] as? Date
        )
    }
}

private extension CloudKitCardMapper {
    static func set(_ value: String, forKey key: String, on record: CKRecord) {
        guard record[key] as? String != value else { return }
        record[key] = value as CKRecordValue
    }

    static func set(_ value: Int, forKey key: String, on record: CKRecord) {
        guard record[key] as? Int != value else { return }
        record[key] = value as CKRecordValue
    }

    static func set(_ value: Date, forKey key: String, on record: CKRecord) {
        guard record[key] as? Date != value else { return }
        record[key] = value as CKRecordValue
    }

    static func set(_ value: Date?, forKey key: String, on record: CKRecord) {
        guard record[key] as? Date != value else { return }
        record[key] = value as CKRecordValue?
    }
}

enum CloudKitHouseholdSelection {
    static let selectedSharedZoneOwnerNameKey = "selectedSharedHouseholdZoneOwnerName"

    static func selectedSharedZoneID() -> CKRecordZone.ID? {
        guard let ownerName = UserDefaults.standard.string(forKey: selectedSharedZoneOwnerNameKey),
              !ownerName.isEmpty else {
            return nil
        }
        return CloudKitCardMapper.zoneID(ownerName: ownerName)
    }

    static func rememberSharedZoneID(_ zoneID: CKRecordZone.ID) {
        guard zoneID.zoneName == CloudKitCardMapper.zoneName else { return }
        UserDefaults.standard.set(zoneID.ownerName, forKey: selectedSharedZoneOwnerNameKey)
    }

    static func clearSelectedSharedZone() {
        UserDefaults.standard.removeObject(forKey: selectedSharedZoneOwnerNameKey)
    }

    static func selectedSharedZoneID(from zoneIDs: [CKRecordZone.ID]) -> CKRecordZone.ID? {
        let householdZoneIDs = sortedHouseholdZoneIDs(from: zoneIDs)

        guard !householdZoneIDs.isEmpty else {
            clearSelectedSharedZone()
            return nil
        }

        if let selected = selectedSharedZoneID(),
           householdZoneIDs.contains(where: { matches($0, selected) }) {
            return selected
        }

        guard householdZoneIDs.count == 1, let selected = householdZoneIDs.first else {
            clearSelectedSharedZone()
            return nil
        }
        rememberSharedZoneID(selected)
        return selected
    }

    static func deletableSharedZoneIDs(from zoneIDs: [CKRecordZone.ID]) -> [CKRecordZone.ID] {
        let householdZoneIDs = sortedHouseholdZoneIDs(from: zoneIDs)

        guard !householdZoneIDs.isEmpty else {
            clearSelectedSharedZone()
            return []
        }

        if let selected = selectedSharedZoneID(),
           let rememberedZoneID = householdZoneIDs.first(where: { matches($0, selected) }) {
            return [rememberedZoneID]
        }

        clearSelectedSharedZone()
        return householdZoneIDs
    }

    private static func sortedHouseholdZoneIDs(from zoneIDs: [CKRecordZone.ID]) -> [CKRecordZone.ID] {
        zoneIDs
            .filter { $0.zoneName == CloudKitCardMapper.zoneName }
            .sorted { lhs, rhs in
                lhs.ownerName.localizedStandardCompare(rhs.ownerName) == .orderedAscending
            }
    }

    private static func matches(_ lhs: CKRecordZone.ID, _ rhs: CKRecordZone.ID) -> Bool {
        lhs.zoneName == rhs.zoneName && lhs.ownerName == rhs.ownerName
    }
}

enum CloudKitMappingError: LocalizedError {
    case missingRequiredField

    var errorDescription: String? {
        "A CloudKit card record is missing a required field."
    }
}
