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

    let cardStore: LocalCardStore
    let checkInStore: LocalCheckInStore
    let parser: BrainDumpParser
    let reminderScheduler: ReminderScheduler
    let syncService: CloudKitSyncService
    let pairingService: CloudKitPairingService
    private var pendingCardsForPush: [LoadCard]?

    init(
        cardStore: LocalCardStore = LocalCardStore(),
        checkInStore: LocalCheckInStore = LocalCheckInStore(),
        parser: BrainDumpParser = FoundationModelsBrainDumpParser(),
        reminderScheduler: ReminderScheduler = LocalReminderScheduler(),
        syncService: CloudKitSyncService = CloudKitSyncService(),
        pairingService: CloudKitPairingService = CloudKitPairingService()
    ) {
        if ProcessInfo.processInfo.arguments.contains("-resetFairNest") {
            UserDefaults.standard.removeObject(forKey: "onboardingComplete")
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
        self.parser = parser
        self.reminderScheduler = reminderScheduler
        self.syncService = syncService
        self.pairingService = pairingService
    }

    func completeOnboarding() {
        onboardingComplete = true
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
            let remote = try await syncService.fetchCards()
            let merged = syncService.merge(local: cardStore.cards, remote: remote)
            try await syncService.upload(cards: merged)
            cardStore.replaceAll(with: merged)
            writeWidgetSnapshot(cards: merged, syncPending: false)
            lastSyncMessage = nil
        } catch {
            writeWidgetSnapshot(cards: cardStore.cards, syncPending: true)
            lastSyncMessage = error.localizedDescription
        }
        await finishSyncAndFlushPending()
    }

    func handleCardsChanged(_ cards: [LoadCard]) async {
        await reconcileDueReminders(for: cards)
        await pushCardsIfAvailable(cards)
    }

    func pushCardsIfAvailable(_ cards: [LoadCard]) async {
        guard iCloudSyncEnabled else { return }
        guard syncService.status == .available else { return }
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

    private func reconcileDueReminders(for cards: [LoadCard]) async {
        let status = await reminderScheduler.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        for card in cards {
            if card.isDeleted || card.status == .done || card.dueDate == nil {
                await reminderScheduler.cancelReminder(for: card.id)
            } else {
                try? await reminderScheduler.scheduleDueTask(card)
            }
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
