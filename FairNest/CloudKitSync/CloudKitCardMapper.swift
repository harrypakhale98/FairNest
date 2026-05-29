import CloudKit
import Foundation

enum CloudKitCardMapper {
    static let recordType = "LoadCard"
    static let zoneName = "FairNestHousehold"

    static func zoneID(ownerName: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    static func recordID(for card: LoadCard, ownerName: String = CKCurrentUserDefaultName) -> CKRecord.ID {
        CKRecord.ID(recordName: card.id.uuidString, zoneID: zoneID(ownerName: ownerName))
    }

    static func record(from card: LoadCard, ownerName: String = CKCurrentUserDefaultName) throws -> CKRecord {
        try record(from: card, zoneID: zoneID(ownerName: ownerName))
    }

    static func record(from card: LoadCard, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: card.id.uuidString, zoneID: zoneID))
        record["title"] = card.title as CKRecordValue
        record["type"] = card.type.rawValue as CKRecordValue
        record["owner"] = card.owner.rawValue as CKRecordValue
        record["status"] = card.status.rawValue as CKRecordValue
        record["effort"] = card.effort.rawValue as CKRecordValue
        record["notes"] = card.notes as CKRecordValue
        record["doneCriteria"] = card.doneCriteria as CKRecordValue
        record["createdBy"] = card.createdBy.rawValue as CKRecordValue
        record["modifiedBy"] = card.modifiedBy.rawValue as CKRecordValue
        record["createdAt"] = card.createdAt as CKRecordValue
        record["updatedAt"] = card.updatedAt as CKRecordValue
        record["dueDate"] = card.dueDate as CKRecordValue?
        record["deletedAt"] = card.deletedAt as CKRecordValue?
        let recurrenceData = try JSONEncoder.fairNest.encode(card.recurrence)
        record["recurrence"] = String(decoding: recurrenceData, as: UTF8.self) as CKRecordValue
        return record
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
        let householdZoneIDs = zoneIDs
            .filter { $0.zoneName == CloudKitCardMapper.zoneName }
            .sorted { lhs, rhs in
                lhs.ownerName.localizedStandardCompare(rhs.ownerName) == .orderedAscending
            }

        guard !householdZoneIDs.isEmpty else {
            clearSelectedSharedZone()
            return nil
        }

        if let selected = selectedSharedZoneID(),
           householdZoneIDs.contains(where: { matches($0, selected) }) {
            return selected
        }

        let selected = householdZoneIDs[0]
        rememberSharedZoneID(selected)
        return selected
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
