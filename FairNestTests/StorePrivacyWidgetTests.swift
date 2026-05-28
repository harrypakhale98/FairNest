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

        PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).deleteAllLocalData()
        XCTAssertTrue(cardStore.cards.isEmpty)
        XCTAssertTrue(checkInStore.records.isEmpty)
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

    func testDeletingLocalDataRemovesTemporaryExports() throws {
        let cardStore = LocalCardStore(fileURL: tempURL())
        let checkInStore = LocalCheckInStore(fileURL: tempURL())
        _ = cardStore.add(BrainDumpSuggestion(title: "Export me", type: .task))
        let service = PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore)
        let exportURL = try service.exportToTemporaryFile()

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        service.deleteAllLocalData()

        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}
