import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppServices: ObservableObject {
    @Published var onboardingComplete: Bool {
        didSet {
            UserDefaults.standard.set(onboardingComplete, forKey: "onboardingComplete")
        }
    }
    @Published var iCloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled")
        }
    }
    @Published private(set) var syncInProgress = false
    @Published private(set) var lastSyncMessage: String?
    @Published private(set) var lastReminderMessage: String?

    let cardStore: LocalCardStore
    let checkInStore: LocalCheckInStore
    let parser: BrainDumpParser
    let reminderScheduler: ReminderScheduler
    let syncService: CloudKitSyncService
    let pairingService: CloudKitPairingService
    private var pendingCardsForPush: [LoadCard]?
    private var suppressNextCardPush = false

    init(
        cardStore: LocalCardStore = LocalCardStore(),
        checkInStore: LocalCheckInStore = LocalCheckInStore(),
        parser: BrainDumpParser? = nil,
        reminderScheduler: ReminderScheduler = LocalReminderScheduler(),
        syncService: CloudKitSyncService = CloudKitSyncService(),
        pairingService: CloudKitPairingService = CloudKitPairingService()
    ) {
        if ProcessInfo.processInfo.arguments.contains("-resetFairNest") {
            UserDefaults.standard.removeObject(forKey: "onboardingComplete")
            UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            UserDefaults.standard.removeObject(forKey: FairNestRouteRequest.openWeeklyCheckInOnLaunchKey)
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestingCompleteOnboarding") {
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
        }
        self.onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        if UserDefaults.standard.object(forKey: "iCloudSyncEnabled") == nil {
            UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
        }
        self.iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        self.cardStore = cardStore
        self.checkInStore = checkInStore
        self.parser = parser ?? Self.defaultParser()
        self.reminderScheduler = reminderScheduler
        self.syncService = syncService
        self.pairingService = pairingService
    }

    private static func defaultParser() -> BrainDumpParser {
        if ProcessInfo.processInfo.arguments.contains("-useRuleBasedParser") {
            return RuleBasedBrainDumpParser()
        }
        return FoundationModelsBrainDumpParser()
    }

    func completeOnboarding() {
        onboardingComplete = true
    }

    func deleteAllLocalDataForPrivacy() async throws {
        try await deleteAllLocalDataForPrivacy(restoresSyncOnFailure: true)
    }

    private func deleteAllLocalDataForPrivacy(restoresSyncOnFailure: Bool) async throws {
        let previousSyncEnabled = iCloudSyncEnabled
        iCloudSyncEnabled = false
        do {
            try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).deleteAllLocalData()
            await reminderScheduler.cancelAllFairNestReminders()
            lastSyncMessage = nil
            lastReminderMessage = nil
            writeWidgetSnapshot(cards: [], syncPending: false)
        } catch {
            if restoresSyncOnFailure {
                iCloudSyncEnabled = previousSyncEnabled
            }
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: false)
            throw error
        }
    }

    func deleteSharedHouseholdDataForPrivacy() async throws {
        iCloudSyncEnabled = false
        var sharedDeletionError: Error?
        do {
            try await syncService.deleteSharedHouseholdData()
        } catch {
            sharedDeletionError = error
        }

        do {
            try await deleteAllLocalDataForPrivacy(restoresSyncOnFailure: false)
        } catch {
            if let sharedDeletionError {
                throw PrivacyDeletionError.sharedAndLocalDeletionFailed(shared: sharedDeletionError, local: error)
            }
            throw error
        }

        if let sharedDeletionError {
            throw sharedDeletionError
        }
    }

    func handleAcceptedCloudKitShare() async {
        iCloudSyncEnabled = true
        pairingService.markShareAccepted()
        await syncCardsIfAvailable()
    }

    func syncCardsIfAvailable() async {
        guard iCloudSyncEnabled else {
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: false)
            return
        }
        guard !syncInProgress else { return }
        syncInProgress = true
        await syncService.refreshStatus()
        guard syncService.status == .available else {
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: syncService.status == .offline || syncService.status == .pending)
            await finishSyncAndFlushPending()
            return
        }
        do {
            let localBeforeFetch = cardStore.cards
            let remote = try await syncService.fetchCards()
            let merged = syncService.merge(local: localBeforeFetch, remote: remote)
            try await syncService.upload(cards: merged)
            let currentLocal = cardStore.cards
            let finalCards = currentLocal == localBeforeFetch ? merged : syncService.merge(local: currentLocal, remote: merged)
            suppressNextCardPush = true
            try cardStore.replaceAllThrowing(with: finalCards)
            if finalCards != merged {
                try await syncService.upload(cards: finalCards)
            }
            writeWidgetSnapshot(cards: finalCards, syncPending: false)
            lastSyncMessage = nil
        } catch {
            suppressNextCardPush = false
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: true)
            lastSyncMessage = error.localizedDescription
        }
        await finishSyncAndFlushPending()
    }

    func handleCardsChanged(_ cards: [LoadCard]) async {
        do {
            try await reconcileDueReminders(for: cards)
            lastReminderMessage = nil
        } catch {
            lastReminderMessage = error.localizedDescription
        }
        if suppressNextCardPush {
            suppressNextCardPush = false
            return
        }
        await pushCardsIfAvailable(cards)
    }

    func scheduleRemindersForCurrentCards() async throws {
        do {
            try await reconcileDueReminders(for: cardStore.cards)
            lastReminderMessage = nil
        } catch {
            lastReminderMessage = error.localizedDescription
            throw error
        }
    }

    func pushCardsIfAvailable(_ cards: [LoadCard]) async {
        guard iCloudSyncEnabled else { return }
        guard syncService.status == .available else {
            if syncInProgress {
                pendingCardsForPush = cards
            } else {
                await syncCardsIfAvailable()
            }
            return
        }
        guard !syncInProgress else {
            pendingCardsForPush = cards
            return
        }
        syncInProgress = true
        do {
            try await syncService.upload(cards: cards)
            writeWidgetSnapshot(cards: cards, syncPending: false)
            lastSyncMessage = nil
        } catch {
            writeWidgetSnapshot(cards: cards, syncPending: true)
            lastSyncMessage = error.localizedDescription
        }
        await finishSyncAndFlushPending()
    }

    private func reconcileDueReminders(for cards: [LoadCard]) async throws {
        let status = await reminderScheduler.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let currentCardIDs = Set(cards.map(\.id))
        let pendingIdentifiers = await reminderScheduler.pendingFairNestReminderIdentifiers()
        for identifier in pendingIdentifiers where ReminderRequestFactory.isCardReminderIdentifier(identifier) {
            guard let cardID = ReminderRequestFactory.cardID(fromReminderIdentifier: identifier),
                  !currentCardIDs.contains(cardID) else { continue }
            await reminderScheduler.cancelReminder(for: cardID)
        }

        var firstSchedulingError: Error?
        let now = Date()
        for card in cards {
            if !ReminderRequestFactory.shouldScheduleDueTask(for: card, now: now) {
                await reminderScheduler.cancelReminder(for: card.id)
            } else {
                do {
                    try await reminderScheduler.scheduleDueTask(card)
                } catch {
                    firstSchedulingError = firstSchedulingError ?? error
                }
            }
        }
        if let firstSchedulingError {
            throw firstSchedulingError
        }
    }

    private func finishSyncAndFlushPending() async {
        syncInProgress = false
        guard let pendingCardsForPush else { return }
        self.pendingCardsForPush = nil
        await pushCardsIfAvailable(pendingCardsForPush)
    }

    private func writeWidgetSnapshot(cards: [LoadCard], syncPending: Bool) {
        WidgetSnapshotStore.write(cards: cards, syncPending: syncPending)
        WidgetSnapshotStore.reloadTimelines()
    }
}

private enum PrivacyDeletionError: LocalizedError {
    case sharedAndLocalDeletionFailed(shared: Error, local: Error)

    var errorDescription: String? {
        switch self {
        case let .sharedAndLocalDeletionFailed(shared, local):
            return "FairNest could not finish deleting shared iCloud data (\(shared.localizedDescription)) or local device data (\(local.localizedDescription)). iCloud Sync remains off so local cards are not uploaded again."
        }
    }
}
