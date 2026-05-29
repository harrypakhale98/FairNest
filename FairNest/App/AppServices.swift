import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppServices: ObservableObject {
    private static let acceptedSharePrivateCardIDsKey = "acceptedSharePrivateCardIDs"
    private static let activeCloudKitAccountIdentifierKey = "activeCloudKitAccountIdentifier"

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
    private let syncEngine: any SyncService
    private var pendingCardsForPush: [LoadCard]?
    private var suppressNextCardPush = false

    init(
        cardStore: LocalCardStore = LocalCardStore(),
        checkInStore: LocalCheckInStore = LocalCheckInStore(),
        parser: BrainDumpParser? = nil,
        reminderScheduler: ReminderScheduler = LocalReminderScheduler(),
        syncService: CloudKitSyncService = CloudKitSyncService(),
        syncEngine: (any SyncService)? = nil,
        pairingService: CloudKitPairingService = CloudKitPairingService()
    ) {
        if ProcessInfo.processInfo.arguments.contains("-resetFairNest") {
            UserDefaults.standard.removeObject(forKey: "onboardingComplete")
            UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
            UserDefaults.standard.removeObject(forKey: Self.acceptedSharePrivateCardIDsKey)
            UserDefaults.standard.removeObject(forKey: Self.activeCloudKitAccountIdentifierKey)
            CloudKitHouseholdSelection.clearSelectedSharedZone()
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
        self.syncEngine = syncEngine ?? syncService
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
            acceptedSharePrivateCardIDs = []
            UserDefaults.standard.removeObject(forKey: Self.activeCloudKitAccountIdentifierKey)
            CloudKitHouseholdSelection.clearSelectedSharedZone()
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
        var sharedDeletionResult: CloudKitHouseholdDeletionResult?
        do {
            sharedDeletionResult = try await syncEngine.deleteSharedHouseholdData()
        } catch let error as CloudKitHouseholdSelectionError {
            throw error
        } catch {
            sharedDeletionError = error
        }

        do {
            try await deleteAllLocalDataForPrivacy(restoresSyncOnFailure: false)
        } catch {
            if let sharedDeletionError {
                throw PrivacyDeletionError.sharedAndLocalDeletionFailed(shared: sharedDeletionError, local: error)
            }
            throw PrivacyDeletionError.localDeletionFailedAfterSharedDeletion(local: error)
        }

        sharedDeletionResult?.acknowledgeErasedZones()

        if let sharedDeletionError {
            throw sharedDeletionError
        }
    }

    func handleAcceptedCloudKitShare() async {
        protectCurrentLocalCardsFromSharedUpload()
        iCloudSyncEnabled = true
        pairingService.markShareAccepted()
        await syncCardsIfAvailable()
    }

    func handleFailedCloudKitShareAcceptance(_ error: Error?) {
        pairingService.markShareAcceptanceFailed(error)
        lastSyncMessage = error?.localizedDescription ?? FairNestIssueCopy.pairingFailure
    }

    func syncCardsIfAvailable() async {
        guard iCloudSyncEnabled else {
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: false)
            return
        }
        applyPrivateUploadPins()
        guard !syncInProgress else { return }
        syncInProgress = true
        await syncEngine.refreshStatus()
        guard syncEngine.status == .available else {
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: syncEngine.status == .offline || syncEngine.status == .pending)
            await finishSyncAndFlushPending()
            return
        }
        guard allowSyncForCurrentCloudKitAccount() else {
            await finishSyncAndFlushPending()
            return
        }
        do {
            let localBeforeFetch = cardStore.cards
            let remote = try await syncEngine.fetchCards()
            let merged = syncEngine.merge(local: localBeforeFetch, remote: remote)
            try await syncEngine.upload(cards: merged)
            let currentLocal = cardStore.cards
            let finalCards = currentLocal == localBeforeFetch ? merged : syncEngine.merge(local: currentLocal, remote: merged)
            suppressNextCardPush = true
            try cardStore.replaceAllThrowing(with: finalCards)
            if finalCards != merged {
                try await syncEngine.upload(cards: finalCards)
            }
            writeWidgetSnapshot(cards: finalCards, syncPending: false)
            lastSyncMessage = nil
        } catch let error as CloudKitHouseholdErasedError {
            await handleRemoteHouseholdErasure(error)
        } catch let error as CloudKitSharedHouseholdUnavailableError {
            handleSharedHouseholdUnavailable(sharedCardIDs: error.sharedCardIDs)
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
        applyPrivateUploadPins()
        if !syncInProgress {
            await syncEngine.refreshStatus()
            guard syncEngine.status == .available else {
                writeWidgetSnapshot(cards: cards, syncPending: syncEngine.status == .offline || syncEngine.status == .pending)
                return
            }
            guard allowSyncForCurrentCloudKitAccount() else { return }
        }
        guard syncEngine.status == .available else {
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
            let localBeforeFetch = cardStore.cards
            let remote = try await syncEngine.fetchCards()
            let merged = syncEngine.merge(local: localBeforeFetch, remote: remote)
            let currentLocal = cardStore.cards
            let finalCards = currentLocal == localBeforeFetch ? merged : syncEngine.merge(local: currentLocal, remote: merged)
            if finalCards != currentLocal {
                suppressNextCardPush = true
                try cardStore.replaceAllThrowing(with: finalCards)
            }
            try await syncEngine.upload(cards: finalCards)
            writeWidgetSnapshot(cards: finalCards, syncPending: false)
            lastSyncMessage = nil
        } catch let error as CloudKitHouseholdErasedError {
            await handleRemoteHouseholdErasure(error)
        } catch let error as CloudKitSharedHouseholdUnavailableError {
            handleSharedHouseholdUnavailable(sharedCardIDs: error.sharedCardIDs)
        } catch {
            suppressNextCardPush = false
            writeWidgetSnapshot(cards: cards, syncPending: true)
            lastSyncMessage = error.localizedDescription
        }
        await finishSyncAndFlushPending()
    }

    private func reconcileDueReminders(for cards: [LoadCard]) async throws {
        let now = Date()
        let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let pendingIdentifiers = await reminderScheduler.pendingFairNestReminderIdentifiers()
        var cancelledReminderCardIDs = Set<UUID>()
        func cancelReminderIfNeeded(for cardID: UUID) async {
            guard cancelledReminderCardIDs.insert(cardID).inserted else { return }
            await reminderScheduler.cancelReminder(for: cardID)
        }

        for identifier in pendingIdentifiers where ReminderRequestFactory.isCardReminderIdentifier(identifier) {
            guard let cardID = ReminderRequestFactory.cardID(fromReminderIdentifier: identifier) else { continue }
            if let card = cardsByID[cardID] {
                guard !ReminderRequestFactory.shouldScheduleDueTask(for: card, now: now) else { continue }
                await cancelReminderIfNeeded(for: cardID)
            } else {
                await cancelReminderIfNeeded(for: cardID)
            }
        }

        let status = await reminderScheduler.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        var firstSchedulingError: Error?
        for card in cards {
            if !ReminderRequestFactory.shouldScheduleDueTask(for: card, now: now) {
                await cancelReminderIfNeeded(for: card.id)
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
        if cards.isEmpty, !syncPending {
            WidgetSnapshotStore.clear()
        } else {
            WidgetSnapshotStore.write(cards: cards, syncPending: syncPending)
        }
        WidgetSnapshotStore.reloadTimelines()
    }

    private func handleRemoteHouseholdErasure(_ error: CloudKitHouseholdErasedError) async {
        iCloudSyncEnabled = false
        pendingCardsForPush = nil
        suppressNextCardPush = true
        CloudKitHouseholdSelection.clearSelectedSharedZone()
        do {
            try cardStore.replaceAllThrowing(with: [])
            await reminderScheduler.cancelAllFairNestReminders()
            writeWidgetSnapshot(cards: [], syncPending: false)
            CloudKitHouseholdErasureState.acknowledge(
                error.erasedAt,
                accountIdentifier: error.accountIdentifier,
                zoneID: error.zoneID
            )
            lastSyncMessage = FairNestIssueCopy.sharedHouseholdErased
        } catch {
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: false)
            lastSyncMessage = FairNestIssueCopy.localCardSaveFailure
        }
    }

    private func handleSharedHouseholdUnavailable(sharedCardIDs: Set<UUID>) {
        iCloudSyncEnabled = false
        pendingCardsForPush = nil
        suppressNextCardPush = false
        let removedUnavailableCards = removeUnavailableSharedCards(sharedCardIDs: sharedCardIDs)
        acceptedSharePrivateCardIDs = []
        CloudKitHouseholdSelection.clearSelectedSharedZone()
        if removedUnavailableCards {
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: false)
            lastSyncMessage = FairNestIssueCopy.sharedHouseholdUnavailable
        } else {
            writeWidgetSnapshot(cards: [], syncPending: false)
            lastSyncMessage = FairNestIssueCopy.localCardSaveFailure
        }
    }

    private func removeUnavailableSharedCards(sharedCardIDs: Set<UUID>) -> Bool {
        guard !sharedCardIDs.isEmpty else {
            return true
        }
        let privateCardIDs = acceptedSharePrivateCardIDs
        let remainingCards = cardStore.cards.filter { card in
            if privateCardIDs.contains(card.id) {
                return true
            }
            return !sharedCardIDs.contains(card.id)
        }
        guard remainingCards != cardStore.cards else { return true }
        do {
            try cardStore.replaceAllThrowing(with: remainingCards)
            return true
        } catch {
            return false
        }
    }

    private func allowSyncForCurrentCloudKitAccount() -> Bool {
        guard let accountIdentifier = syncEngine.accountIdentifier else {
            return true
        }

        let previousIdentifier = UserDefaults.standard.string(forKey: Self.activeCloudKitAccountIdentifierKey)
        guard let previousIdentifier, previousIdentifier != accountIdentifier else {
            UserDefaults.standard.set(accountIdentifier, forKey: Self.activeCloudKitAccountIdentifierKey)
            return true
        }

        iCloudSyncEnabled = false
        pendingCardsForPush = nil
        suppressNextCardPush = false
        acceptedSharePrivateCardIDs = []
        CloudKitHouseholdSelection.clearSelectedSharedZone()
        UserDefaults.standard.set(accountIdentifier, forKey: Self.activeCloudKitAccountIdentifierKey)
        writeWidgetSnapshot(cards: cardStore.cards, syncPending: false)
        lastSyncMessage = FairNestIssueCopy.iCloudAccountChanged
        return false
    }

    private func protectCurrentLocalCardsFromSharedUpload() {
        let localCardIDs = Set(cardStore.cards.map(\.id))
        guard !localCardIDs.isEmpty else { return }
        var pinnedCardIDs = acceptedSharePrivateCardIDs
        pinnedCardIDs.formUnion(localCardIDs)
        acceptedSharePrivateCardIDs = pinnedCardIDs
        syncEngine.pinCardsToPrivateDatabase(localCardIDs)
    }

    private func applyPrivateUploadPins() {
        syncEngine.pinCardsToPrivateDatabase(acceptedSharePrivateCardIDs)
    }

    private var acceptedSharePrivateCardIDs: Set<UUID> {
        get {
            let values = UserDefaults.standard.stringArray(forKey: Self.acceptedSharePrivateCardIDsKey) ?? []
            return Set(values.compactMap(UUID.init(uuidString:)))
        }
        set {
            let values = newValue.map(\.uuidString).sorted()
            UserDefaults.standard.set(values, forKey: Self.acceptedSharePrivateCardIDsKey)
        }
    }
}

enum PrivacyDeletionError: LocalizedError {
    case sharedAndLocalDeletionFailed(shared: Error, local: Error)
    case localDeletionFailedAfterSharedDeletion(local: Error)

    var errorDescription: String? {
        switch self {
        case let .sharedAndLocalDeletionFailed(shared, local):
            return "FairNest could not finish deleting shared iCloud data (\(shared.localizedDescription)) or local device data (\(local.localizedDescription)). iCloud Sync remains off so local cards are not uploaded again."
        case let .localDeletionFailedAfterSharedDeletion(local):
            return "FairNest could not finish deleting local device data after the shared iCloud deletion step (\(local.localizedDescription)). iCloud Sync remains off so old cards are not uploaded again."
        }
    }
}
