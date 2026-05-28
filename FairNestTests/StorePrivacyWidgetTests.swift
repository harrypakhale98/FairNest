import XCTest
@testable import FairNest

@MainActor
final class StorePrivacyWidgetTests: XCTestCase {
    func testCreateEditCompleteExportAndDeleteData() throws {
        let cardURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let checkInURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let cardStore = LocalCardStore(fileURL: cardURL)
        let checkInStore = LocalCheckInStore(fileURL: checkInURL)

        let card = cardStore.add(BrainDumpSuggestion(title: "Buy milk", type: .task, owner: .me))
        cardStore.reassign(id: card.id, to: .shared)
        try cardStore.transition(id: card.id, to: .done)

        XCTAssertEqual(cardStore.activeCards.first?.owner, .shared)
        XCTAssertEqual(cardStore.activeCards.first?.status, .done)

        let export = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportData()
        XCTAssertFalse(export.isEmpty)

        try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).deleteAllLocalData()
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertTrue(checkInStore.records.isEmpty)
    }

    func testPrivacyExportIncludesCheckInContents() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        let record = CheckInRecord(
            feltHeavy: "Meal planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: [OwnershipChange(title: "Trash", owner: .partner, reason: "Reviewed")]
        )
        try checkInStore.save(record)

        let data = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportData()
        let export = try JSONDecoder.fairNest.decode(FairNestExportEnvelope.self, from: data)

        XCTAssertEqual(export.checkIns, [record])
    }

    func testOnboardingCompletionPersists() {
        let services = AppServices(cardStore: LocalCardStore(fileURL: tempURL()), checkInStore: LocalCheckInStore(fileURL: tempURL()))
        services.onboardingComplete = false

        services.completeOnboarding()

        XCTAssertTrue(services.onboardingComplete)
    }

    func testICloudSyncDefaultsToLocalOnly() {
        let previousValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
        }

        let services = AppServices(cardStore: LocalCardStore(fileURL: tempURL()), checkInStore: LocalCheckInStore(fileURL: tempURL()))

        XCTAssertFalse(services.iCloudSyncEnabled)
    }

    func testPairingUnavailableStatesHaveClearCopy() {
        XCTAssertEqual(PairingState.notSignedIn.title, "Sign in to iCloud")
        XCTAssertTrue(PairingState.offline.message.contains("locally"))
        XCTAssertTrue(PairingState.permissionDenied.message.contains("permission"))
    }

    func testShareAcceptanceFailureMovesPairingIntoActionableError() {
        let service = CloudKitPairingService()

        service.markShareAcceptanceFailed(TestPairingError.expiredInvite)

        XCTAssertEqual(service.state, .error("Invite expired"))
    }

    func testAcceptedShareEnablesSyncBeforeMarkingPaired() async {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
        }
        let services = AppServices(cardStore: LocalCardStore(fileURL: tempURL()), checkInStore: LocalCheckInStore(fileURL: tempURL()))
        services.iCloudSyncEnabled = false

        await services.handleAcceptedCloudKitShare()

        XCTAssertTrue(services.iCloudSyncEnabled)
        XCTAssertEqual(services.pairingService.state, .paired)
    }

    func testInviteCreationIsBlockedWhenAlreadyPaired() {
        XCTAssertTrue(PairingState.solo.allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertTrue(PairingState.partnerNotJoined.allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertTrue(PairingState.sharingRemoved.allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertFalse(PairingState.paired.allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertFalse(PairingState.error("Expired invite").allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertFalse(PairingState.solo.allowsCreatingInvite(iCloudSyncEnabled: false))
    }

    func testWidgetTimelineScheduleIncludesReload() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dates = WidgetTimelineSchedule.reloadDates(now: now)

        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(dates.first, now)
        XCTAssertGreaterThan(dates.last!, now)
    }

    func testWidgetSnapshotsDoNotPersistPrivateCardTitles() throws {
        let privateTitle = "Buy private medication"
        let card = LoadCard(title: privateTitle, type: .reminder, owner: .me, status: .planned, effort: .light)
        let summaries = WidgetSnapshotStore.summaries(for: [card])

        XCTAssertEqual(summaries.first?.displayTitle, "Reminder")

        let data = try JSONEncoder.fairNest.encode(summaries)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(privateTitle))
    }

    func testWidgetSnapshotClearRemovesStoredMetadata() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let card = LoadCard(title: "Private title", type: .task, owner: .partner, status: .planned, effort: .heavy)

        XCTAssertTrue(WidgetSnapshotStore.write(cards: [card], defaults: defaults))
        XCTAssertFalse(WidgetSnapshotStore.read(defaults: defaults).cards.isEmpty)

        XCTAssertTrue(WidgetSnapshotStore.clear(defaults: defaults))
        XCTAssertTrue(WidgetSnapshotStore.read(defaults: defaults).cards.isEmpty)
    }

    func testWidgetSnapshotWriteAndClearReportUnavailableDefaults() {
        XCTAssertFalse(WidgetSnapshotStore.write(cards: [], defaults: nil))
        XCTAssertFalse(WidgetSnapshotStore.clear(defaults: nil))
    }

    func testPrivacyManifestDeclaresUserDefaultsRequiredReasonAPI() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FairNest/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let accessedAPIs = plist?["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        let userDefaultsEntry = accessedAPIs?.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = userDefaultsEntry?["NSPrivacyAccessedAPITypeReasons"] as? [String]

        XCTAssertEqual(plist?["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue(reasons?.contains("CA92.1") == true)
        XCTAssertTrue(reasons?.contains("1C8F.1") == true)
    }

    func testWidgetPrivacyManifestDeclaresUserDefaultsRequiredReasonAPI() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FairNestWidgets/Supporting/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let accessedAPIs = plist?["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        let userDefaultsEntry = accessedAPIs?.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = userDefaultsEntry?["NSPrivacyAccessedAPITypeReasons"] as? [String]

        XCTAssertEqual(plist?["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue(reasons?.contains("CA92.1") == true)
        XCTAssertTrue(reasons?.contains("1C8F.1") == true)
    }

    func testCorruptLocalStoresAreBackedUpBeforeReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cardURL = directory.appendingPathComponent("cards.json")
        let checkInURL = directory.appendingPathComponent("checkins.json")
        try Data("not json".utf8).write(to: cardURL)
        try Data("not json".utf8).write(to: checkInURL)

        _ = LocalCardStore(fileURL: cardURL)
        _ = LocalCheckInStore(fileURL: checkInURL)

        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("cards.json.corrupt.") })
        XCTAssertTrue(backups.contains { $0.hasPrefix("checkins.json.corrupt.") })
    }

    func testDeletingLocalDataRemovesCorruptBackups() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cardURL = directory.appendingPathComponent("cards.json")
        let checkInURL = directory.appendingPathComponent("checkins.json")
        try Data("not json".utf8).write(to: cardURL)
        try Data("not json".utf8).write(to: checkInURL)
        let cardStore = LocalCardStore(fileURL: cardURL)
        let checkInStore = LocalCheckInStore(fileURL: checkInURL)

        cardStore.deleteAllLocalData()
        try checkInStore.deleteAll()

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("cards.json.corrupt.") })
        XCTAssertFalse(files.contains { $0.hasPrefix("checkins.json.corrupt.") })
    }

    func testDeletingLocalDataRemovesTemporaryExports() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        _ = cardStore.add(BrainDumpSuggestion(title: "Export me", type: .task))
        let service = PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore)
        let exportURL = try service.exportToTemporaryFile()

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        try service.deleteAllLocalData()

        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
    }

    func testExportToTemporaryFileRemovesPreviousTemporaryExport() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        let service = PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore)

        let firstExportURL = try service.exportToTemporaryFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstExportURL.path))
        let secondExportURL = try service.exportToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: secondExportURL) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstExportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondExportURL.path))
    }

    func testPrivacyExportDeleteRestoresLocalDataWhenCheckInDeleteFails() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInURL = tempURL()
        let checkInStore = LocalCheckInStore(fileURL: checkInURL)
        let card = cardStore.add(BrainDumpSuggestion(title: "Keep me", type: .task))
        let record = CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: []
        )
        try checkInStore.save(record)
        try FileManager.default.removeItem(at: checkInURL)
        try FileManager.default.createDirectory(at: checkInURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).deleteAllLocalData())

        XCTAssertEqual(cardStore.cards.first?.id, card.id)
        XCTAssertEqual(checkInStore.records, [record])
    }

    func testPrivacyDeleteRestoresSyncAndLocalDataWhenLocalDeleteFails() async throws {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
        }
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInURL = tempURL()
        let checkInStore = LocalCheckInStore(fileURL: checkInURL)
        let card = cardStore.add(BrainDumpSuggestion(title: "Keep private", type: .task))
        let record = CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: []
        )
        try checkInStore.save(record)
        try FileManager.default.removeItem(at: checkInURL)
        try FileManager.default.createDirectory(at: checkInURL, withIntermediateDirectories: true)
        let services = AppServices(cardStore: cardStore, checkInStore: checkInStore)
        services.iCloudSyncEnabled = true

        do {
            try await services.deleteAllLocalDataForPrivacy()
            XCTFail("Expected privacy deletion to surface the local persistence failure.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertTrue(services.iCloudSyncEnabled)
        XCTAssertEqual(cardStore.cards.first?.id, card.id)
        XCTAssertEqual(checkInStore.records, [record])
    }

    func testSharedPrivacyDeleteKeepsSyncOffAndClearsLocalDataWhenCloudKitFails() async throws {
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
        _ = cardStore.add(BrainDumpSuggestion(title: "Do not re-upload", type: .task))
        try checkInStore.save(CheckInRecord(
            feltHeavy: "Planning",
            gotDone: "Laundry",
            needsOwnership: "Trash",
            appreciation: "Dinner",
            changes: []
        ))
        let services = AppServices(cardStore: cardStore, checkInStore: checkInStore)
        services.iCloudSyncEnabled = true

        do {
            try await services.deleteSharedHouseholdDataForPrivacy()
            XCTFail("Expected CloudKit deletion to fail in the test runtime.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertTrue(checkInStore.records.isEmpty)
    }

    func testCheckInStoreRollsBackWhenPersistenceFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unusableStoreURL = directory.appendingPathComponent("checkins.json", isDirectory: true)
        try FileManager.default.createDirectory(at: unusableStoreURL, withIntermediateDirectories: true)
        let checkInStore = LocalCheckInStore(fileURL: unusableStoreURL)

        XCTAssertThrowsError(try checkInStore.save(CheckInRecord(
            feltHeavy: "Private",
            gotDone: "",
            needsOwnership: "",
            appreciation: "",
            changes: []
        )))
        XCTAssertTrue(checkInStore.records.isEmpty)
        XCTAssertFalse(checkInStore.lastPersistenceErrorMessage?.isEmpty ?? true)
    }

    func testWidgetWeeklyOverviewIgnoresFarFutureCards() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let thisWeek = WidgetCardSummary(
            id: UUID(),
            type: .task,
            owner: .me,
            effort: .medium,
            dueDate: calendar.date(byAdding: .day, value: 2, to: now),
            status: .planned
        )
        let future = WidgetCardSummary(
            id: UUID(),
            type: .task,
            owner: .partner,
            effort: .heavy,
            dueDate: calendar.date(byAdding: .day, value: 30, to: now),
            status: .planned
        )
        let snapshot = WidgetHouseholdSnapshot(generatedAt: now, syncPending: false, cards: [thisWeek, future])

        XCTAssertEqual(snapshot.weeklyCards(now: now, calendar: calendar), [thisWeek])
        XCTAssertEqual(snapshot.weeklyEffortScore(now: now, calendar: calendar), Effort.medium.rawValue)
    }

    func testReviewedBrainDumpSaveDoesNotClearIntoMemoryWhenPersistenceFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let unusableStoreURL = directory.appendingPathComponent("cards.json", isDirectory: true)
        try FileManager.default.createDirectory(at: unusableStoreURL, withIntermediateDirectories: true)
        let cardStore = LocalCardStore(fileURL: unusableStoreURL)

        XCTAssertThrowsError(try cardStore.addReviewed([
            BrainDumpSuggestion(title: "Do not lose me", type: .task)
        ]))
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertFalse(cardStore.lastPersistenceErrorMessage?.isEmpty ?? true)
    }

    func testBoardUpsertRollsBackWhenPersistenceFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let unusableStoreURL = directory.appendingPathComponent("cards.json", isDirectory: true)
        try FileManager.default.createDirectory(at: unusableStoreURL, withIntermediateDirectories: true)
        let cardStore = LocalCardStore(fileURL: unusableStoreURL)

        XCTAssertThrowsError(try cardStore.upsertThrowing(LoadCard(title: "Do not keep in memory")))

        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertFalse(cardStore.lastPersistenceErrorMessage?.isEmpty ?? true)
    }

    func testBoardDeleteRollsBackWhenPersistenceFails() throws {
        let fileURL = tempURL()
        let cardStore = LocalCardStore(fileURL: fileURL)
        let card = LoadCard(title: "Keep me")
        try cardStore.upsertThrowing(card)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try cardStore.deleteThrowing(id: card.id))

        XCTAssertEqual(cardStore.cards.first?.id, card.id)
        XCTAssertFalse(cardStore.cards.first?.isDeleted ?? true)
        XCTAssertFalse(cardStore.lastPersistenceErrorMessage?.isEmpty ?? true)
    }

    func testEditorStyleUpsertRunsRecurringDoneTransition() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let card = LoadCard(title: "Water plants", status: .planned, dueDate: now, recurrence: .daily, updatedAt: now)
        try cardStore.upsertThrowing(card, at: now)
        var edited = card
        edited.status = .done

        try cardStore.upsertThrowing(edited, at: now)

        XCTAssertEqual(cardStore.cards.first?.status, .planned)
        XCTAssertNotNil(cardStore.cards.first?.dueDate)
        XCTAssertGreaterThan(cardStore.cards.first!.dueDate!, now)
    }

    func testStaleEditorSaveCannotResurrectRemovedCard() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let card = LoadCard(title: "Remove me")
        try cardStore.upsertThrowing(card)
        try cardStore.deleteThrowing(id: card.id)

        XCTAssertThrowsError(try cardStore.upsertThrowing(card))

        XCTAssertTrue(cardStore.cards.first?.isDeleted == true)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}

private enum TestPairingError: LocalizedError {
    case expiredInvite

    var errorDescription: String? {
        switch self {
        case .expiredInvite:
            return "Invite expired"
        }
    }
}
