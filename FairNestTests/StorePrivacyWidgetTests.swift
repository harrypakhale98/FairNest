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

    func testPrivacyExportRefusesIncompleteCardStore() throws {
        let unreadableCardURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unreadableCardURL, withIntermediateDirectories: true)
        let cardStore = LocalCardStore(fileURL: unreadableCardURL)
        let checkInStore = LocalCheckInStore(fileURL: tempURL())

        XCTAssertThrowsError(try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportData()) { error in
            XCTAssertTrue(error.localizedDescription.contains("did not create an incomplete export"))
        }
    }

    func testPrivacyExportRefusesIncompleteCheckInStore() throws {
        let unreadableCheckInURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unreadableCheckInURL, withIntermediateDirectories: true)
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: unreadableCheckInURL)

        XCTAssertThrowsError(try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportData()) { error in
            XCTAssertTrue(error.localizedDescription.contains("did not create an incomplete export"))
        }
    }

    func testPrivacyExportRefusesBackedUpCorruptCardStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cardURL = directory.appendingPathComponent("cards.json")
        try Data("not json".utf8).write(to: cardURL)
        let cardStore = LocalCardStore(fileURL: cardURL)
        let checkInStore = LocalCheckInStore(fileURL: tempURL())

        XCTAssertThrowsError(try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportData()) { error in
            XCTAssertTrue(error.localizedDescription.contains("did not create an incomplete export"))
        }
    }

    func testPrivacyExportRefusesBackedUpCorruptCheckInStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let checkInURL = directory.appendingPathComponent("checkins.json")
        try Data("not json".utf8).write(to: checkInURL)
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: checkInURL)

        XCTAssertThrowsError(try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportData()) { error in
            XCTAssertTrue(error.localizedDescription.contains("did not create an incomplete export"))
        }
    }

    func testDeletedCardTombstoneRedactsLocalContentAndPrivacyExport() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        let originalCreatedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let sensitiveCard = LoadCard(
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
            createdAt: originalCreatedAt,
            modifiedBy: .partner
        )
        try cardStore.upsertThrowing(sensitiveCard)
        try cardStore.deleteThrowing(id: sensitiveCard.id)
        let storedCard = try XCTUnwrap(cardStore.cards.first)

        let data = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportData()
        let export = try JSONDecoder.fairNest.decode(FairNestExportEnvelope.self, from: data)
        let exportedCard = try XCTUnwrap(export.cards.first)
        let deletionDate = try XCTUnwrap(exportedCard.deletedAt)

        XCTAssertEqual(storedCard, exportedCard)
        XCTAssertTrue(exportedCard.isDeleted)
        XCTAssertEqual(exportedCard.id, sensitiveCard.id)
        XCTAssertEqual(exportedCard.title, "")
        XCTAssertEqual(exportedCard.type, .task)
        XCTAssertEqual(exportedCard.owner, .unassigned)
        XCTAssertEqual(exportedCard.status, .done)
        XCTAssertEqual(exportedCard.effort, .tiny)
        XCTAssertNil(exportedCard.dueDate)
        XCTAssertEqual(exportedCard.recurrence, .none)
        XCTAssertEqual(exportedCard.notes, "")
        XCTAssertEqual(exportedCard.doneCriteria, "")
        XCTAssertEqual(exportedCard.createdBy, .system)
        XCTAssertEqual(exportedCard.createdAt, deletionDate)
        XCTAssertNotEqual(exportedCard.createdAt, originalCreatedAt)
        XCTAssertEqual(exportedCard.modifiedBy, .system)
        XCTAssertEqual(exportedCard.updatedAt, deletionDate)
    }

    func testDeletedCardCanBeRestoredFromTransientSnapshot() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let sensitiveCard = LoadCard(
            title: "Private medication refill",
            type: .reminder,
            owner: .partner,
            status: .planned,
            effort: .heavy,
            notes: "Sensitive dosage note",
            doneCriteria: "Prescription picked up"
        )
        try cardStore.upsertThrowing(sensitiveCard)
        try cardStore.deleteThrowing(id: sensitiveCard.id)

        XCTAssertEqual(cardStore.cards.first?.title, "")
        XCTAssertThrowsError(try cardStore.restoreThrowing(id: sensitiveCard.id))
        let deletedAt = try XCTUnwrap(cardStore.cards.first?.deletedAt)

        try cardStore.restoreThrowing(sensitiveCard, matchingDeletedAt: deletedAt)

        let restoredCard = try XCTUnwrap(cardStore.activeCards.first)
        XCTAssertEqual(restoredCard.title, "Private medication refill")
        XCTAssertEqual(restoredCard.notes, "Sensitive dosage note")
        XCTAssertFalse(restoredCard.isDeleted)
    }

    func testUndoRestoreCannotResurrectNewerDeletionTombstone() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let original = LoadCard(
            id: UUID(),
            title: "Private medication refill",
            type: .reminder,
            owner: .me,
            status: .planned,
            effort: .light,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try cardStore.upsertThrowing(original, by: .me, at: Date(timeIntervalSince1970: 1_800_000_000))
        try cardStore.deleteThrowing(id: original.id)
        let localDeletedAt = try XCTUnwrap(cardStore.cards.first?.deletedAt)
        var newerRemoteTombstone = original
        let newerDeletedAt = localDeletedAt.addingTimeInterval(60)
        newerRemoteTombstone.softDelete(at: newerDeletedAt, by: .partner)
        try cardStore.replaceAllThrowing(with: [newerRemoteTombstone])

        XCTAssertThrowsError(try cardStore.restoreThrowing(original, matchingDeletedAt: localDeletedAt))

        let remainingCard = try XCTUnwrap(cardStore.cards.first)
        XCTAssertTrue(remainingCard.isDeleted)
        XCTAssertEqual(remainingCard.deletedAt, newerDeletedAt)
        XCTAssertEqual(remainingCard.title, "")
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

    func testAppVersionLabelIncludesVersionAndBuildForSupport() {
        XCTAssertEqual(
            FairNestAppMetadata.versionLabel(infoDictionary: [
                "CFBundleShortVersionString": "1.2",
                "CFBundleVersion": "34"
            ]),
            "1.2 (34)"
        )
        XCTAssertEqual(
            FairNestAppMetadata.versionLabel(infoDictionary: [
                "CFBundleShortVersionString": "1.2",
                "CFBundleVersion": "1.2"
            ]),
            "1.2"
        )
        XCTAssertEqual(FairNestAppMetadata.versionLabel(infoDictionary: [:]), "Unknown")
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
        XCTAssertEqual(service.state.message, "Invite expired")
        XCTAssertNil(service.shareAcceptanceMessage)
    }

    func testPairingModeLabelsMatchPendingAndErrorStates() {
        XCTAssertEqual(PairingState.solo.modeLabel, "Solo-ready")
        XCTAssertEqual(PairingState.paired.modeLabel, "Shared")
        XCTAssertEqual(PairingState.partnerNotJoined.modeLabel, "Invite pending")
        XCTAssertEqual(PairingState.syncPending.modeLabel, "Sync pending")
        XCTAssertEqual(PairingState.error("Invite expired").modeLabel, "Needs attention")
        XCTAssertEqual(PairingState.permissionDenied.modeLabel, "Needs permission")
    }

    func testAcceptedShareEnablesSyncBeforeMarkingPaired() async {
        let previousSyncValue = UserDefaults.standard.object(forKey: "iCloudSyncEnabled")
        let previousPairingRoute = UserDefaults.standard.object(forKey: FairNestRouteRequest.openPairingOnLaunchKey)
        defer {
            if let previousSyncValue {
                UserDefaults.standard.set(previousSyncValue, forKey: "iCloudSyncEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            }
            if let previousPairingRoute {
                UserDefaults.standard.set(previousPairingRoute, forKey: FairNestRouteRequest.openPairingOnLaunchKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FairNestRouteRequest.openPairingOnLaunchKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: FairNestRouteRequest.openPairingOnLaunchKey)
        let services = AppServices(cardStore: LocalCardStore(fileURL: tempURL()), checkInStore: LocalCheckInStore(fileURL: tempURL()))
        services.iCloudSyncEnabled = false
        let routeExpectation = expectation(description: "Accepted share routes to Pair")
        let observer = NotificationCenter.default.addObserver(forName: .fairNestOpenPairing, object: nil, queue: nil) { _ in
            routeExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await services.handleAcceptedCloudKitShare()
        await fulfillment(of: [routeExpectation], timeout: 1)

        XCTAssertTrue(services.iCloudSyncEnabled)
        XCTAssertEqual(services.pairingService.state, .paired)
        XCTAssertEqual(services.pairingService.shareAcceptanceMessage, "You're paired. Shared household cards will sync through iCloud.")
    }

    func testFailedShareAcceptanceRoutesToPairing() async {
        let previousPairingRoute = UserDefaults.standard.object(forKey: FairNestRouteRequest.openPairingOnLaunchKey)
        defer {
            if let previousPairingRoute {
                UserDefaults.standard.set(previousPairingRoute, forKey: FairNestRouteRequest.openPairingOnLaunchKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FairNestRouteRequest.openPairingOnLaunchKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: FairNestRouteRequest.openPairingOnLaunchKey)
        let services = AppServices(cardStore: LocalCardStore(fileURL: tempURL()), checkInStore: LocalCheckInStore(fileURL: tempURL()))
        let routeExpectation = expectation(description: "Failed share routes to Pair")
        let observer = NotificationCenter.default.addObserver(forName: .fairNestOpenPairing, object: nil, queue: nil) { _ in
            routeExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        services.handleFailedCloudKitShareAcceptance(TestPairingError.expiredInvite)
        await fulfillment(of: [routeExpectation], timeout: 1)

        XCTAssertEqual(services.pairingService.state, .error("Invite expired"))
        XCTAssertEqual(services.lastSyncMessage, "Invite expired")
    }

    func testInviteCreationIsBlockedWhenAlreadyPaired() {
        XCTAssertTrue(PairingState.solo.allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertTrue(PairingState.partnerNotJoined.allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertTrue(PairingState.sharingRemoved.allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertFalse(PairingState.paired.allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertFalse(PairingState.error("Expired invite").allowsCreatingInvite(iCloudSyncEnabled: true))
        XCTAssertFalse(PairingState.solo.allowsCreatingInvite(iCloudSyncEnabled: false))
    }

    func testSharedPrivacyDeletionRequiresSharedHouseholdState() {
        XCTAssertTrue(PairingState.partnerNotJoined.allowsSharedHouseholdPrivacyDeletion)
        XCTAssertTrue(PairingState.paired.allowsSharedHouseholdPrivacyDeletion)
        XCTAssertFalse(PairingState.solo.allowsSharedHouseholdPrivacyDeletion)
        XCTAssertFalse(PairingState.sharingRemoved.allowsSharedHouseholdPrivacyDeletion)
        XCTAssertFalse(PairingState.error("Expired invite").allowsSharedHouseholdPrivacyDeletion)
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

    func testWidgetSnapshotReadSanitizesLegacyPrivateDisplayTitles() throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let privateTitle = "Private medication"
        let legacySnapshot = WidgetHouseholdSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            syncPending: false,
            cards: [
                WidgetCardSummary(
                    id: UUID(),
                    type: .reminder,
                    owner: .me,
                    effort: .light,
                    dueDate: nil,
                    status: .planned,
                    displayTitle: privateTitle
                )
            ]
        )
        let data = try JSONEncoder.fairNest.encode(legacySnapshot)
        defaults.set(data, forKey: FairNestShared.widgetSnapshotKey)

        let snapshot = WidgetSnapshotStore.read(defaults: defaults)

        XCTAssertEqual(snapshot.cards.first?.displayTitle, "Reminder")
        XCTAssertFalse(snapshot.cards.contains { $0.displayTitle == privateTitle })
    }

    func testWidgetSnapshotKeepsOpenCardsWhenDoneCardsHitSnapshotLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let openCard = LoadCard(
            id: UUID(),
            title: "Open card",
            type: .task,
            owner: .shared,
            status: .inbox,
            effort: .medium,
            dueDate: nil,
            updatedAt: now
        )
        let doneCards = (0..<25).map { index in
            LoadCard(
                id: UUID(),
                title: "Done \(index)",
                type: .task,
                owner: .me,
                status: .done,
                effort: .tiny,
                dueDate: now.addingTimeInterval(TimeInterval(-index - 1) * 3_600),
                updatedAt: now.addingTimeInterval(TimeInterval(index + 1))
            )
        }

        let summaries = WidgetSnapshotStore.summaries(for: doneCards + [openCard])

        XCTAssertEqual(summaries.count, 25)
        XCTAssertEqual(summaries.first?.id, openCard.id)
        XCTAssertTrue(summaries.contains { $0.id == openCard.id })
        XCTAssertEqual(summaries.filter { $0.status == .done }.count, 24)
    }

    func testWidgetNextResponsibilityIsEmptyWhenAllCardsAreDone() {
        let doneCard = WidgetCardSummary(
            id: UUID(),
            type: .task,
            owner: .me,
            effort: .tiny,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            status: .done
        )
        let snapshot = WidgetHouseholdSnapshot(generatedAt: Date(), syncPending: false, cards: [doneCard])

        XCTAssertNil(snapshot.nextResponsibility)
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

    func testReleaseInfoPlistDeclaresPortraitOnlyIPhoneOrientation() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FairNest/Supporting/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertEqual(plist?["UISupportedInterfaceOrientations"] as? [String], ["UIInterfaceOrientationPortrait"])
    }

    func testWebsiteCopyIsLaunchNeutral() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let index = try String(contentsOf: repositoryURL.appendingPathComponent("website/index.html"), encoding: .utf8)
        let privacy = try String(contentsOf: repositoryURL.appendingPathComponent("website/privacy.html"), encoding: .utf8)

        XCTAssertFalse(index.contains("Coming to iPhone"))
        XCTAssertFalse(privacy.contains("Coming to iPhone"))
        XCTAssertTrue(index.contains("Built for iPhone"))
        XCTAssertTrue(privacy.contains("Built for iPhone"))
    }

    func testInAppPrivacyPolicyUsesBundledDeletionMarkerDisclosure() throws {
        let bundledPolicy = try XCTUnwrap(PrivacyPolicyContent.bundledMarkdown())

        XCTAssertTrue(PrivacyPolicyContent.summary.contains("minimal deletion markers"))
        XCTAssertTrue(PrivacyPolicyContent.summary.contains("local storage"))
        XCTAssertTrue(PrivacyPolicyContent.summary.contains("Invited participants"))
        XCTAssertTrue(bundledPolicy.contains("minimal deletion marker"))
        XCTAssertTrue(bundledPolicy.contains("omit the card title"))
        XCTAssertTrue(bundledPolicy.contains("local storage"))
        XCTAssertTrue(bundledPolicy.contains("withdraw optional iCloud Sync"))
        XCTAssertTrue(bundledPolicy.contains("Local FairNest data remains"))
        XCTAssertTrue(bundledPolicy.contains("harry.pakhale98@gmail.com"))
    }

    func testPrivacyPolicyDetailUsesReadableSections() throws {
        let bundledPolicy = try XCTUnwrap(PrivacyPolicyContent.bundledMarkdown())
        let sections = PrivacyPolicyContent.sections(from: bundledPolicy)

        XCTAssertGreaterThanOrEqual(sections.count, 6)
        XCTAssertEqual(sections.first?.title, "Overview")
        XCTAssertTrue(sections.contains { $0.title == "User Controls" })
        XCTAssertTrue(sections.contains { $0.title == "Deletion Markers" })
        XCTAssertFalse(sections.contains { $0.body.contains("# FairNest Privacy Policy") })
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

    func testCorruptCardStoreClearsWidgetSnapshot() throws {
        let defaults = try XCTUnwrap(FairNestShared.sharedDefaults)
        WidgetSnapshotStore.clear(defaults: defaults)
        defer { WidgetSnapshotStore.clear(defaults: defaults) }
        let card = LoadCard(title: "Private widget title", type: .task, owner: .shared, status: .planned, effort: .medium)
        XCTAssertTrue(WidgetSnapshotStore.write(cards: [card], defaults: defaults))
        XCTAssertFalse(WidgetSnapshotStore.read(defaults: defaults).cards.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cardURL = directory.appendingPathComponent("cards.json")
        try Data("not json".utf8).write(to: cardURL)

        _ = LocalCardStore(fileURL: cardURL)

        XCTAssertTrue(WidgetSnapshotStore.read(defaults: defaults).cards.isEmpty)
    }

    func testUnreadableCardStoreClearsWidgetSnapshot() throws {
        let defaults = try XCTUnwrap(FairNestShared.sharedDefaults)
        WidgetSnapshotStore.clear(defaults: defaults)
        defer { WidgetSnapshotStore.clear(defaults: defaults) }
        let card = LoadCard(title: "Private widget title", type: .task, owner: .shared, status: .planned, effort: .medium)
        XCTAssertTrue(WidgetSnapshotStore.write(cards: [card], defaults: defaults))
        XCTAssertFalse(WidgetSnapshotStore.read(defaults: defaults).cards.isEmpty)
        let unreadableCardURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unreadableCardURL, withIntermediateDirectories: true)

        _ = LocalCardStore(fileURL: unreadableCardURL)

        XCTAssertTrue(WidgetSnapshotStore.read(defaults: defaults).cards.isEmpty)
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
            XCTAssertEqual(
                FairNestIssueCopy.localDeleteFailure,
                "FairNest couldn't finish deleting all local data. Your previous iCloud Sync setting was restored; check details before trying again."
            )
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
            XCTAssertEqual(FairNestIssueCopy.sharedDeleteFailureMessage(for: error), FairNestIssueCopy.sharedDeleteCloudFailure)
        }

        XCTAssertFalse(services.iCloudSyncEnabled)
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertTrue(checkInStore.records.isEmpty)
    }

    func testCheckInStoreRollsBackWhenPersistenceFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unusableStoreURL = directory.appendingPathComponent("checkins.json")
        let checkInStore = LocalCheckInStore(fileURL: unusableStoreURL)
        try FileManager.default.createDirectory(at: unusableStoreURL, withIntermediateDirectories: true)

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
        let unusableStoreURL = directory.appendingPathComponent("cards.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cardStore = LocalCardStore(fileURL: unusableStoreURL)
        try FileManager.default.removeItem(at: unusableStoreURL)
        try FileManager.default.createDirectory(at: unusableStoreURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try cardStore.addReviewed([
            BrainDumpSuggestion(title: "Do not lose me", type: .task)
        ]))
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertFalse(cardStore.lastPersistenceErrorMessage?.isEmpty ?? true)
    }

    func testBoardUpsertRollsBackWhenPersistenceFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let unusableStoreURL = directory.appendingPathComponent("cards.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cardStore = LocalCardStore(fileURL: unusableStoreURL)
        try FileManager.default.removeItem(at: unusableStoreURL)
        try FileManager.default.createDirectory(at: unusableStoreURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try cardStore.upsertThrowing(LoadCard(title: "Do not keep in memory")))

        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertFalse(cardStore.lastPersistenceErrorMessage?.isEmpty ?? true)
    }

    func testCardStoreBlocksWritesAfterReadFailure() throws {
        let unreadableStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unreadableStoreURL, withIntermediateDirectories: true)
        let cardStore = LocalCardStore(fileURL: unreadableStoreURL)

        XCTAssertFalse(cardStore.lastLoadErrorMessage?.isEmpty ?? true)
        XCTAssertThrowsError(try cardStore.upsertThrowing(LoadCard(title: "Do not overwrite"))) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not read the local card store"))
        }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreadableStoreURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(cardStore.cards.isEmpty)
    }

    func testCheckInStoreBlocksWritesAfterReadFailure() throws {
        let unreadableStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unreadableStoreURL, withIntermediateDirectories: true)
        let checkInStore = LocalCheckInStore(fileURL: unreadableStoreURL)

        XCTAssertFalse(checkInStore.lastLoadErrorMessage?.isEmpty ?? true)
        XCTAssertThrowsError(try checkInStore.save(CheckInRecord(
            feltHeavy: "Do not overwrite",
            gotDone: "",
            needsOwnership: "",
            appreciation: "",
            changes: []
        ))) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not read the local check-in store"))
        }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreadableStoreURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(checkInStore.records.isEmpty)
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

    func testStaleEditorSaveDoesNotOverwriteNewerCard() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let openedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let openedCard = LoadCard(title: "Original", updatedAt: openedAt)
        try cardStore.upsertThrowing(openedCard, at: openedAt)
        let revision = CardRevision(card: try XCTUnwrap(cardStore.cards.first))
        let newerSyncedCard = LoadCard(id: openedCard.id, title: "Synced title", updatedAt: syncedAt)
        try cardStore.replaceAllThrowing(with: [newerSyncedCard])
        var staleEdit = openedCard
        staleEdit.title = "Stale edit"

        XCTAssertThrowsError(try cardStore.upsertThrowing(staleEdit, expectedRevision: revision)) { error in
            XCTAssertEqual(error.localizedDescription, FairNestIssueCopy.staleCardEdit)
        }

        XCTAssertEqual(cardStore.cards.first?.title, "Synced title")
        XCTAssertEqual(cardStore.cards.first?.updatedAt, syncedAt)
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
