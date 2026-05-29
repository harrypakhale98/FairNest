import CloudKit
import XCTest
import UserNotifications
@testable import FairNest

final class SyncAndCloudKitTests: XCTestCase {
    func testConflictResolutionUsesLatestUpdatedAt() {
        let id = UUID()
        let older = LoadCard(id: id, title: "Older", updatedAt: Date(timeIntervalSince1970: 10))
        let newer = LoadCard(id: id, title: "Newer", updatedAt: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(ConflictResolver.resolve(local: older, remote: newer).title, "Newer")
        XCTAssertEqual(ConflictResolver.resolve(local: newer, remote: older).title, "Newer")
    }

    func testConflictResolutionPrefersNewerDeletedTombstoneOverStaleActiveCard() {
        let id = UUID()
        var newerDeleted = LoadCard(
            id: id,
            title: "Deleted",
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        newerDeleted.softDelete(at: Date(timeIntervalSince1970: 20))
        let olderActive = LoadCard(
            id: id,
            title: "Stale device edit",
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertTrue(ConflictResolver.resolve(local: olderActive, remote: newerDeleted).isDeleted)
        XCTAssertTrue(ConflictResolver.resolve(local: newerDeleted, remote: olderActive).isDeleted)
    }

    func testConflictResolutionAllowsNewerRestoreToBeatOlderTombstone() {
        let id = UUID()
        var olderDeleted = LoadCard(
            id: id,
            title: "Deleted",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        olderDeleted.softDelete(at: Date(timeIntervalSince1970: 10))
        let restoredActive = LoadCard(
            id: id,
            title: "Restored card",
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(ConflictResolver.resolve(local: restoredActive, remote: olderDeleted).title, "Restored card")
        XCTAssertEqual(ConflictResolver.resolve(local: olderDeleted, remote: restoredActive).title, "Restored card")
    }

    func testConflictResolutionPrefersTombstoneWhenDeleteAndActiveTie() {
        let id = UUID()
        var deleted = LoadCard(
            id: id,
            title: "Deleted",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        deleted.softDelete(at: Date(timeIntervalSince1970: 10))
        let active = LoadCard(
            id: id,
            title: "Same timestamp",
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertTrue(ConflictResolver.resolve(local: active, remote: deleted).isDeleted)
        XCTAssertTrue(ConflictResolver.resolve(local: deleted, remote: active).isDeleted)
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

    func testCloudKitMappingAppliesUpdatesToExistingRecordWithoutDroppingUnknownFields() throws {
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
        record["serverOnly"] = "keep me" as CKRecordValue
        var updatedCard = card
        updatedCard.title = "Pay utilities today"
        updatedCard.notes = "Check autopay first"
        updatedCard.updatedAt = Date(timeIntervalSince1970: 1_700_000_200)

        try CloudKitCardMapper.apply(updatedCard, to: record)
        let mapped = try CloudKitCardMapper.card(from: record)

        XCTAssertEqual(mapped.title, "Pay utilities today")
        XCTAssertEqual(mapped.notes, "Check autopay first")
        XCTAssertEqual(record["serverOnly"] as? String, "keep me")
    }

    func testCloudKitMappingRedactsDeletedCardContent() throws {
        var card = LoadCard(
            id: UUID(),
            title: "Private medication refill",
            type: .reminder,
            owner: .partner,
            status: .planned,
            effort: .heavy,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            recurrence: .weekly(weekday: 3),
            notes: "Sensitive dosage note",
            doneCriteria: "Prescription picked up",
            createdBy: .partner,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedBy: .partner,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        card.softDelete(at: Date(timeIntervalSince1970: 1_700_000_200), by: .me)

        let record = try CloudKitCardMapper.record(from: card)
        let mapped = try CloudKitCardMapper.card(from: record)

        XCTAssertTrue(mapped.isDeleted)
        XCTAssertEqual(mapped.id, card.id)
        XCTAssertEqual(mapped.title, "")
        XCTAssertEqual(mapped.type, .task)
        XCTAssertEqual(mapped.owner, .unassigned)
        XCTAssertEqual(mapped.status, .done)
        XCTAssertEqual(mapped.effort, .tiny)
        XCTAssertNil(mapped.dueDate)
        XCTAssertEqual(mapped.recurrence, .none)
        XCTAssertEqual(mapped.notes, "")
        XCTAssertEqual(mapped.doneCriteria, "")
        XCTAssertEqual(mapped.createdBy, .system)
        XCTAssertEqual(mapped.modifiedBy, .system)
        XCTAssertEqual(mapped.updatedAt, card.updatedAt)
        XCTAssertEqual(mapped.deletedAt, card.deletedAt)
    }

    func testCloudKitCardsUseHouseholdZone() throws {
        let card = LoadCard(id: UUID(), title: "Rotate laundry")
        let record = try CloudKitCardMapper.record(from: card)

        XCTAssertEqual(record.recordID.zoneID.zoneName, CloudKitCardMapper.zoneName)
        XCTAssertEqual(record.recordID.recordName, card.id.uuidString)
    }

    func testHouseholdErasureMarkerUsesExistingCardSchemaWithoutUserContent() throws {
        let erasedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = try CloudKitCardMapper.householdErasureMarkerRecord(
            erasedAt: erasedAt,
            zoneID: CloudKitCardMapper.zoneID()
        )

        XCTAssertTrue(CloudKitCardMapper.isHouseholdErasureMarker(record.recordID))
        XCTAssertEqual(CloudKitCardMapper.householdErasureDate(from: record), erasedAt)

        let marker = try CloudKitCardMapper.card(from: record)
        XCTAssertTrue(CloudKitCardMapper.isHouseholdErasureMarker(marker.id))
        XCTAssertEqual(marker.title, "")
        XCTAssertTrue(marker.isDeleted)
        XCTAssertEqual(marker.updatedAt, erasedAt)
    }

    func testSharedHouseholdZoneSelectionRequiresRememberedOwnerWhenMultipleSharesExist() {
        let previousSelection = UserDefaults.standard.object(forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey)
        defer {
            if let previousSelection {
                UserDefaults.standard.set(previousSelection, forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey)
            } else {
                CloudKitHouseholdSelection.clearSelectedSharedZone()
            }
        }

        CloudKitHouseholdSelection.clearSelectedSharedZone()
        let ownerB = CloudKitCardMapper.zoneID(ownerName: "owner-b")
        let ownerA = CloudKitCardMapper.zoneID(ownerName: "owner-a")
        let unrelated = CKRecordZone.ID(zoneName: "OtherZone", ownerName: "owner-0")

        let initialSelection = CloudKitHouseholdSelection.selectedSharedZoneID(from: [ownerB, unrelated, ownerA])

        XCTAssertNil(initialSelection)
        XCTAssertNil(UserDefaults.standard.string(forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey))

        let singleSelection = CloudKitHouseholdSelection.selectedSharedZoneID(from: [ownerA, unrelated])

        XCTAssertEqual(singleSelection?.ownerName, "owner-a")
        XCTAssertEqual(UserDefaults.standard.string(forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey), "owner-a")

        CloudKitHouseholdSelection.rememberSharedZoneID(ownerB)
        let rememberedSelection = CloudKitHouseholdSelection.selectedSharedZoneID(from: [ownerA, ownerB])

        XCTAssertEqual(rememberedSelection?.ownerName, "owner-b")
    }

    func testSharedHouseholdDeletionFailsClosedWhenSelectionIsAmbiguous() throws {
        let previousSelection = UserDefaults.standard.object(forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey)
        defer {
            if let previousSelection {
                UserDefaults.standard.set(previousSelection, forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey)
            } else {
                CloudKitHouseholdSelection.clearSelectedSharedZone()
            }
        }

        CloudKitHouseholdSelection.clearSelectedSharedZone()
        let ownerB = CloudKitCardMapper.zoneID(ownerName: "owner-b")
        let ownerA = CloudKitCardMapper.zoneID(ownerName: "owner-a")
        let unrelated = CKRecordZone.ID(zoneName: "OtherZone", ownerName: "owner-0")

        XCTAssertThrowsError(try CloudKitHouseholdSelection.deletableSharedZoneIDs(from: [ownerB, unrelated, ownerA])) { error in
            XCTAssertEqual(error as? CloudKitHouseholdSelectionError, .ambiguousSharedHouseholdDeletion)
        }
        XCTAssertNil(UserDefaults.standard.string(forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey))

        let singleDeletionTarget = try CloudKitHouseholdSelection.deletableSharedZoneIDs(from: [ownerA, unrelated])
        XCTAssertEqual(singleDeletionTarget.map(\.ownerName), ["owner-a"])

        CloudKitHouseholdSelection.clearSelectedSharedZone()
        CloudKitHouseholdSelection.rememberSharedZoneID(ownerB)
        let rememberedDeletionTargets = try CloudKitHouseholdSelection.deletableSharedZoneIDs(from: [ownerA, ownerB])

        XCTAssertEqual(rememberedDeletionTargets.map(\.ownerName), ["owner-b"])
    }

    func testHouseholdErasureAcknowledgementIsScopedByAccountAndZone() throws {
        let suiteName = "FairNestTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let erasedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let zoneA = CloudKitCardMapper.zoneID(ownerName: "owner-a")
        let zoneB = CloudKitCardMapper.zoneID(ownerName: "owner-b")

        CloudKitHouseholdErasureState.acknowledge(
            erasedAt,
            accountIdentifier: "account-a",
            zoneID: zoneA,
            defaults: defaults
        )

        XCTAssertFalse(CloudKitHouseholdErasureState.requiresAcknowledgement(
            erasedAt,
            accountIdentifier: "account-a",
            zoneID: zoneA,
            defaults: defaults
        ))
        XCTAssertTrue(CloudKitHouseholdErasureState.requiresAcknowledgement(
            erasedAt,
            accountIdentifier: "account-b",
            zoneID: zoneA,
            defaults: defaults
        ))
        XCTAssertTrue(CloudKitHouseholdErasureState.requiresAcknowledgement(
            erasedAt,
            accountIdentifier: "account-a",
            zoneID: zoneB,
            defaults: defaults
        ))
    }

    func testLegacyHouseholdErasureAcknowledgementDoesNotSuppressScopedMarker() throws {
        let suiteName = "FairNestTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let erasedAt = Date(timeIntervalSince1970: 1_800_000_000)

        CloudKitHouseholdErasureState.acknowledge(erasedAt, defaults: defaults)

        XCTAssertFalse(CloudKitHouseholdErasureState.requiresAcknowledgement(erasedAt, defaults: defaults))
        XCTAssertTrue(CloudKitHouseholdErasureState.requiresAcknowledgement(
            erasedAt,
            accountIdentifier: "account-a",
            zoneID: CloudKitCardMapper.zoneID(ownerName: "owner-a"),
            defaults: defaults
        ))
    }

    @MainActor
    func testAcceptedSharePinsExistingLocalCardsToPrivateDatabase() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousPins = UserDefaults.standard.object(forKey: "acceptedSharePrivateCardIDs")
        let previousPendingShare = UserDefaults.standard.object(forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
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
            if let previousPendingShare {
                UserDefaults.standard.set(previousPendingShare, forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: "acceptedSharePrivateCardIDs")
        UserDefaults.standard.set(true, forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
        let cardStore = LocalCardStore(fileURL: tempURL())
        let localCard = cardStore.add(BrainDumpSuggestion(title: "Local only", type: .task))
        let deletedLocalCard = cardStore.add(BrainDumpSuggestion(title: "Deleted local only", type: .task))
        try cardStore.deleteThrowing(id: deletedLocalCard.id)
        let services = AppServices(cardStore: cardStore, checkInStore: LocalCheckInStore(fileURL: tempURL()))

        await services.handleAcceptedCloudKitShare()

        XCTAssertTrue(services.syncService.isPinnedToPrivateDatabaseForTesting(localCard.id))
        XCTAssertTrue(services.syncService.isPinnedToPrivateDatabaseForTesting(deletedLocalCard.id))
        let pinnedIDs = UserDefaults.standard.stringArray(forKey: "acceptedSharePrivateCardIDs") ?? []
        XCTAssertTrue(pinnedIDs.contains(localCard.id.uuidString))
        XCTAssertTrue(pinnedIDs.contains(deletedLocalCard.id.uuidString))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey))
    }

    @MainActor
    func testPendingAcceptedShareIsConsumedBeforeStartupSync() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousPins = UserDefaults.standard.object(forKey: "acceptedSharePrivateCardIDs")
        let previousPendingShare = UserDefaults.standard.object(forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
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
            if let previousPendingShare {
                UserDefaults.standard.set(previousPendingShare, forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: "acceptedSharePrivateCardIDs")
        UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
        UserDefaults.standard.set(true, forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
        let cardStore = LocalCardStore(fileURL: tempURL())
        let localCard = cardStore.add(BrainDumpSuggestion(title: "Local before invite", type: .task))
        let syncEngine = CapturingSyncEngine(status: .available, remoteCards: [])
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            syncEngine: syncEngine
        )

        let consumed = await services.consumePendingAcceptedCloudKitShareIfNeeded()

        XCTAssertTrue(consumed)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey))
        XCTAssertTrue(services.iCloudSyncEnabled)
        XCTAssertTrue(syncEngine.pinnedCardIDs.contains(localCard.id))
        XCTAssertEqual(syncEngine.fetchCount, 1)
        XCTAssertEqual(syncEngine.uploadedBatches.count, 1)
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

    func testHouseholdDeletionDoesNotMaskPermissionFailureAfterPartialDelete() throws {
        var progress = CloudKitHouseholdDeletionProgress()
        progress.markDeletedData()
        progress.recordPermissionFailure(TestCloudKitPartialFailure())

        XCTAssertTrue(progress.deletedData)
        XCTAssertThrowsError(try progress.throwPermissionFailureIfPresent()) { error in
            XCTAssertEqual(error.localizedDescription, "Simulated partial failure")
        }
    }

    @MainActor
    func testHouseholdDeletionWritesErasureMarkerBeforeDeletingCards() async throws {
        let executor = RecordingHouseholdDeletionExecutor()
        let zoneID = CloudKitCardMapper.zoneID(ownerName: "owner-a")
        let erasedAt = Date(timeIntervalSince1970: 1_800_000_000)

        try await CloudKitHouseholdDeletionWorkflow.eraseHouseholdData(
            in: executor,
            zoneID: zoneID,
            erasedAt: erasedAt
        )

        XCTAssertEqual(executor.operations, ["saveMarker", "deleteCards"])
        XCTAssertEqual(executor.savedZoneIDs, [zoneID])
        XCTAssertEqual(executor.deletedZoneIDs, [zoneID])
        XCTAssertEqual(executor.savedErasedAt, erasedAt)
    }

    @MainActor
    func testHouseholdDeletionDoesNotDeleteCardsWhenErasureMarkerSaveFails() async {
        let executor = RecordingHouseholdDeletionExecutor(saveError: TestCloudKitPartialFailure())
        let zoneID = CloudKitCardMapper.zoneID(ownerName: "owner-a")

        do {
            try await CloudKitHouseholdDeletionWorkflow.eraseHouseholdData(
                in: executor,
                zoneID: zoneID,
                erasedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            XCTFail("Expected marker save failure to abort shared household deletion.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Simulated partial failure")
            XCTAssertEqual(executor.operations, ["saveMarker"])
            XCTAssertEqual(executor.deletedZoneIDs, [])
        }
    }

    @MainActor
    func testPushCardsFetchesAndMergesRemoteBeforeUploading() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
        }
        let id = UUID()
        let olderLocal = LoadCard(id: id, title: "Older local", updatedAt: Date(timeIntervalSince1970: 10))
        let newerRemote = LoadCard(id: id, title: "Newer remote", updatedAt: Date(timeIntervalSince1970: 20))
        let cardStore = LocalCardStore(fileURL: tempURL())
        try cardStore.replaceAllThrowing(with: [olderLocal])
        let syncEngine = CapturingSyncEngine(status: .available, remoteCards: [newerRemote])
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        await services.pushCardsIfAvailable(cardStore.cards)

        XCTAssertEqual(syncEngine.fetchCount, 1)
        XCTAssertEqual(syncEngine.uploadedBatches.last?.first?.title, "Newer remote")
        XCTAssertEqual(cardStore.cards.first?.title, "Newer remote")
    }

    @MainActor
    func testRemoteHouseholdErasureClearsLocalCardsAndStopsReupload() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousErasureAck = UserDefaults.standard.object(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
            if let previousErasureAck {
                UserDefaults.standard.set(previousErasureAck, forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
        let erasedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cardStore = LocalCardStore(fileURL: tempURL())
        _ = cardStore.add(BrainDumpSuggestion(title: "Stale shared card", type: .task))
        let reminderScheduler = ErasureReminderScheduler()
        let syncEngine = CapturingSyncEngine(
            status: .available,
            remoteCards: [],
            fetchError: CloudKitHouseholdErasedError(erasedAt: erasedAt)
        )
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            reminderScheduler: reminderScheduler,
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        await services.syncCardsIfAvailable()

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertTrue(syncEngine.uploadedBatches.isEmpty)
        XCTAssertTrue(reminderScheduler.cancelledAllFairNestReminders)
        XCTAssertFalse(CloudKitHouseholdErasureState.requiresAcknowledgement(erasedAt))
    }

    @MainActor
    func testRemoteHouseholdErasureKeepsAcknowledgementPendingWhenLocalWipeFails() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousErasureAck = UserDefaults.standard.object(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
            if let previousErasureAck {
                UserDefaults.standard.set(previousErasureAck, forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
        let erasedAt = Date(timeIntervalSince1970: 1_800_000_001)
        let cardURL = tempURL()
        let cardStore = LocalCardStore(fileURL: cardURL)
        let card = cardStore.add(BrainDumpSuggestion(title: "Still local until deletion is durable", type: .task))
        try FileManager.default.removeItem(at: cardURL)
        try FileManager.default.createDirectory(at: cardURL, withIntermediateDirectories: true)
        let syncEngine = CapturingSyncEngine(
            status: .available,
            remoteCards: [],
            fetchError: CloudKitHouseholdErasedError(erasedAt: erasedAt)
        )
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        await services.syncCardsIfAvailable()

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertEqual(cardStore.cards.map(\.id), [card.id])
        XCTAssertEqual(services.lastSyncMessage, FairNestIssueCopy.localCardSaveFailure)
        XCTAssertTrue(CloudKitHouseholdErasureState.requiresAcknowledgement(erasedAt))
    }

    @MainActor
    func testSharedHouseholdAccessLossPreservesLocalCardsWhenSharedIDsAreUnknown() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousPins = UserDefaults.standard.object(forKey: "acceptedSharePrivateCardIDs")
        let previousSelection = UserDefaults.standard.object(forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey)
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
            if let previousSelection {
                UserDefaults.standard.set(previousSelection, forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey)
            } else {
                CloudKitHouseholdSelection.clearSelectedSharedZone()
            }
        }
        CloudKitHouseholdSelection.rememberSharedZoneID(CloudKitCardMapper.zoneID(ownerName: "owner-a"))
        UserDefaults.standard.set([UUID().uuidString], forKey: "acceptedSharePrivateCardIDs")
        let cardStore = LocalCardStore(fileURL: tempURL())
        _ = cardStore.add(BrainDumpSuggestion(title: "Stale shared card", type: .task))
        let widgetDefaults = try XCTUnwrap(FairNestShared.sharedDefaults)
        defer { widgetDefaults.removeObject(forKey: FairNestShared.widgetSnapshotKey) }
        XCTAssertTrue(WidgetSnapshotStore.write(cards: cardStore.cards, defaults: widgetDefaults))
        XCTAssertFalse(WidgetSnapshotStore.read(defaults: widgetDefaults).cards.isEmpty)
        let syncEngine = CapturingSyncEngine(
            status: .available,
            remoteCards: [],
            fetchError: CloudKitSharedHouseholdUnavailableError()
        )
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        await services.pushCardsIfAvailable(cardStore.cards)

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertEqual(syncEngine.fetchCount, 1)
        XCTAssertTrue(syncEngine.uploadedBatches.isEmpty)
        XCTAssertEqual(cardStore.cards.map(\.title), ["Stale shared card"])
        XCTAssertNil(UserDefaults.standard.string(forKey: CloudKitHouseholdSelection.selectedSharedZoneOwnerNameKey))
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "acceptedSharePrivateCardIDs"), [])
        XCTAssertFalse(WidgetSnapshotStore.read(defaults: widgetDefaults).cards.isEmpty)
        XCTAssertEqual(services.lastSyncMessage, FairNestIssueCopy.sharedHouseholdUnavailable)
    }

    @MainActor
    func testSharedHouseholdAccessLossPreservesPinnedPrivateCards() async throws {
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
        let cardStore = LocalCardStore(fileURL: tempURL())
        let privateCard = cardStore.add(BrainDumpSuggestion(title: "Private card", type: .task))
        let sharedCard = cardStore.add(BrainDumpSuggestion(title: "Shared card", type: .task))
        UserDefaults.standard.set([privateCard.id.uuidString], forKey: "acceptedSharePrivateCardIDs")
        let syncEngine = CapturingSyncEngine(
            status: .available,
            remoteCards: [],
            fetchError: CloudKitSharedHouseholdUnavailableError(sharedCardIDs: [sharedCard.id])
        )
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        await services.pushCardsIfAvailable(cardStore.cards)

        XCTAssertEqual(cardStore.cards.map(\.id), [privateCard.id])
        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertEqual(services.lastSyncMessage, FairNestIssueCopy.sharedHouseholdUnavailable)
    }

    @MainActor
    func testCloudKitAccountChangeTurnsOffSyncBeforeUploadingLocalCards() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousAccount = UserDefaults.standard.object(forKey: "activeCloudKitAccountIdentifier")
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
            if let previousAccount {
                UserDefaults.standard.set(previousAccount, forKey: "activeCloudKitAccountIdentifier")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeCloudKitAccountIdentifier")
            }
        }
        UserDefaults.standard.set("old-account", forKey: "activeCloudKitAccountIdentifier")
        let cardStore = LocalCardStore(fileURL: tempURL())
        _ = cardStore.add(BrainDumpSuggestion(title: "Old household card", type: .task))
        let syncEngine = CapturingSyncEngine(status: .available, remoteCards: [], accountIdentifier: "new-account")
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: LocalCheckInStore(fileURL: tempURL()),
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        await services.pushCardsIfAvailable(cardStore.cards)

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertTrue(syncEngine.uploadedBatches.isEmpty)
        XCTAssertEqual(services.lastSyncMessage, FairNestIssueCopy.iCloudAccountChanged)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "activeCloudKitAccountIdentifier"), "new-account")
    }

    @MainActor
    func testSharedPrivacyDeleteDoesNotClearLocalDataWhenSharedSelectionIsAmbiguous() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
        }
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        let card = cardStore.add(BrainDumpSuggestion(title: "Keep until household is clear", type: .task))
        let checkIn = CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: []
        )
        try checkInStore.save(checkIn)
        let syncEngine = CapturingSyncEngine(
            status: .available,
            remoteCards: [],
            deleteSharedHouseholdDataError: CloudKitHouseholdSelectionError.ambiguousSharedHouseholdDeletion
        )
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: checkInStore,
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        do {
            try await services.deleteSharedHouseholdDataForPrivacy()
            XCTFail("Expected ambiguous shared-household deletion to fail before clearing local data.")
        } catch {
            XCTAssertEqual(error as? CloudKitHouseholdSelectionError, .ambiguousSharedHouseholdDeletion)
            XCTAssertEqual(FairNestIssueCopy.sharedDeleteFailureMessage(for: error), FairNestIssueCopy.sharedDeleteSelectionFailure)
        }

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertEqual(syncEngine.deleteSharedHouseholdDataCallCount, 1)
        XCTAssertEqual(cardStore.cards.map(\.id), [card.id])
        XCTAssertEqual(checkInStore.records, [checkIn])
    }

    @MainActor
    func testLocalPrivacyDeleteClearsCloudKitErasureAcknowledgements() async throws {
        let previousAcknowledgements = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in
            key == CloudKitHouseholdErasureState.acknowledgedErasedAtKey ||
                key.hasPrefix("\(CloudKitHouseholdErasureState.acknowledgedErasedAtKey).")
        }
        let unrelatedKey = "FairNestTests.unrelatedErasureValue"
        let previousUnrelatedValue = UserDefaults.standard.object(forKey: unrelatedKey)
        defer {
            CloudKitHouseholdErasureState.clearAllAcknowledgements()
            for (key, value) in previousAcknowledgements {
                UserDefaults.standard.set(value, forKey: key)
            }
            if let previousUnrelatedValue {
                UserDefaults.standard.set(previousUnrelatedValue, forKey: unrelatedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: unrelatedKey)
            }
        }
        CloudKitHouseholdErasureState.clearAllAcknowledgements()
        UserDefaults.standard.set("keep me", forKey: unrelatedKey)
        let erasedAt = Date(timeIntervalSince1970: 1_800_000_010)
        CloudKitHouseholdErasureState.acknowledge(erasedAt)
        CloudKitHouseholdErasureState.acknowledge(
            erasedAt,
            accountIdentifier: "account-a",
            zoneID: CloudKitCardMapper.zoneID(ownerName: "owner-a")
        )
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        _ = cardStore.add(BrainDumpSuggestion(title: "Delete locally", type: .task))
        try checkInStore.save(CheckInRecord(
            feltHeavy: "Admin",
            gotDone: "Dishes",
            needsOwnership: "Groceries",
            appreciation: "Coffee",
            changes: []
        ))
        let services = AppServices(cardStore: cardStore, checkInStore: checkInStore)

        try await services.deleteAllLocalDataForPrivacy()

        let remainingKeys = UserDefaults.standard.dictionaryRepresentation().keys
        XCTAssertFalse(remainingKeys.contains(CloudKitHouseholdErasureState.acknowledgedErasedAtKey))
        XCTAssertFalse(remainingKeys.contains { $0.hasPrefix("\(CloudKitHouseholdErasureState.acknowledgedErasedAtKey).") })
        XCTAssertEqual(UserDefaults.standard.string(forKey: unrelatedKey), "keep me")
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertTrue(checkInStore.records.isEmpty)
    }

    @MainActor
    func testSharedPrivacyDeleteDoesNotAcknowledgeCloudErasureWhenLocalDeleteFails() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousErasureAck = UserDefaults.standard.object(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
            if let previousErasureAck {
                UserDefaults.standard.set(previousErasureAck, forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: CloudKitHouseholdErasureState.acknowledgedErasedAtKey)
        let erasedAt = Date(timeIntervalSince1970: 1_800_000_002)
        let zoneID = CloudKitCardMapper.zoneID()
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInURL = tempURL()
        let checkInStore = LocalCheckInStore(fileURL: checkInURL)
        _ = cardStore.add(BrainDumpSuggestion(title: "Do not acknowledge yet", type: .task))
        let checkIn = CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: []
        )
        try checkInStore.save(checkIn)
        try FileManager.default.removeItem(at: checkInURL)
        try FileManager.default.createDirectory(at: checkInURL, withIntermediateDirectories: true)
        let syncEngine = CapturingSyncEngine(
            status: .available,
            remoteCards: [],
            deleteSharedHouseholdDataResult: CloudKitHouseholdDeletionResult(
                erasedAt: erasedAt,
                accountIdentifier: nil,
                erasedZoneIDs: [zoneID]
            )
        )
        let services = AppServices(
            cardStore: cardStore,
            checkInStore: checkInStore,
            syncEngine: syncEngine
        )
        services.iCloudSyncEnabled = true

        do {
            try await services.deleteSharedHouseholdDataForPrivacy()
            XCTFail("Expected local deletion failure to keep CloudKit erasure acknowledgement pending.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertEqual(FairNestIssueCopy.sharedDeleteFailureMessage(for: error), FairNestIssueCopy.sharedDeleteLocalFailure)
        }

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertEqual(syncEngine.deleteSharedHouseholdDataCallCount, 1)
        XCTAssertEqual(checkInStore.records, [checkIn])
        XCTAssertTrue(CloudKitHouseholdErasureState.requiresAcknowledgement(erasedAt))
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

@MainActor
private final class RecordingHouseholdDeletionExecutor: CloudKitHouseholdDeletionExecutor {
    var operations: [String] = []
    var savedZoneIDs: [CKRecordZone.ID] = []
    var deletedZoneIDs: [CKRecordZone.ID] = []
    var savedErasedAt: Date?
    var saveError: Error?
    var deleteError: Error?

    init(saveError: Error? = nil, deleteError: Error? = nil) {
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func saveHouseholdErasureMarker(zoneID: CKRecordZone.ID, erasedAt: Date) async throws {
        operations.append("saveMarker")
        savedZoneIDs.append(zoneID)
        savedErasedAt = erasedAt
        if let saveError {
            throw saveError
        }
    }

    func deleteCardRecords(zoneID: CKRecordZone.ID) async throws {
        operations.append("deleteCards")
        deletedZoneIDs.append(zoneID)
        if let deleteError {
            throw deleteError
        }
    }
}

@MainActor
private final class CapturingSyncEngine: SyncService {
    var status: SyncStatus
    var accountIdentifier: String?
    var remoteCards: [LoadCard]
    var fetchError: Error?
    var deleteSharedHouseholdDataError: Error?
    var deleteSharedHouseholdDataResult: CloudKitHouseholdDeletionResult
    var uploadedBatches: [[LoadCard]] = []
    var fetchCount = 0
    var deleteSharedHouseholdDataCallCount = 0
    var pinnedCardIDs = Set<UUID>()

    init(
        status: SyncStatus,
        remoteCards: [LoadCard],
        fetchError: Error? = nil,
        deleteSharedHouseholdDataError: Error? = nil,
        deleteSharedHouseholdDataResult: CloudKitHouseholdDeletionResult = .empty,
        accountIdentifier: String? = nil
    ) {
        self.status = status
        self.remoteCards = remoteCards
        self.fetchError = fetchError
        self.deleteSharedHouseholdDataError = deleteSharedHouseholdDataError
        self.deleteSharedHouseholdDataResult = deleteSharedHouseholdDataResult
        self.accountIdentifier = accountIdentifier
    }

    func refreshStatus() async {}

    func merge(local: [LoadCard], remote: [LoadCard]) -> [LoadCard] {
        ConflictResolver.merge(local: local, remote: remote)
    }

    func upload(cards: [LoadCard]) async throws {
        uploadedBatches.append(cards)
    }

    func fetchCards() async throws -> [LoadCard] {
        fetchCount += 1
        if let fetchError {
            throw fetchError
        }
        return remoteCards
    }

    func synchronize(local cards: [LoadCard]) async throws -> [LoadCard] {
        let merged = merge(local: cards, remote: remoteCards)
        try await upload(cards: merged)
        return merged
    }

    func deleteSharedHouseholdData() async throws -> CloudKitHouseholdDeletionResult {
        deleteSharedHouseholdDataCallCount += 1
        if let deleteSharedHouseholdDataError {
            throw deleteSharedHouseholdDataError
        }
        return deleteSharedHouseholdDataResult
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {}

    func pinCardsToPrivateDatabase(_ cardIDs: Set<UUID>) {
        pinnedCardIDs.formUnion(cardIDs)
    }
}

@MainActor
private final class ErasureReminderScheduler: ReminderScheduler {
    var cancelledAllFairNestReminders = false

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func pendingFairNestReminderIdentifiers() async -> [String] {
        []
    }

    func scheduleDueTask(_ card: LoadCard) async throws {}

    func scheduleWeeklyCheckIn(weekday: Int, hour: Int, minute: Int) async throws {}

    func cancelReminder(for cardID: UUID) async {}

    func cancelAllFairNestReminders() async {
        cancelledAllFairNestReminders = true
    }
}
