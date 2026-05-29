import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var services: AppServices

    var body: some View {
        Group {
            if services.onboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .task {
            await refreshAndSync()
        }
        .onChange(of: services.cardStore.cards) { _, cards in
            Task {
                await services.handleCardsChanged(cards)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fairNestAcceptedCloudKitShare)) { _ in
            Task {
                await services.handleAcceptedCloudKitShare()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fairNestFailedCloudKitShareAcceptance)) { notification in
            services.handleFailedCloudKitShareAcceptance(notification.object as? Error)
        }
        .onChange(of: services.iCloudSyncEnabled) { _, enabled in
            Task {
                if enabled {
                    await services.pairingService.refresh()
                }
                await services.syncCardsIfAvailable()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshAndSync()
            }
        }
    }

    private func refreshAndSync() async {
        if await services.consumePendingAcceptedCloudKitShareIfNeeded() {
            return
        }
        if services.iCloudSyncEnabled {
            await services.pairingService.refresh()
        }
        await services.syncCardsIfAvailable()
    }
}

struct MainTabView: View {
    @State private var selection: MainTab = .board

    var body: some View {
        TabView(selection: $selection) {
            HomeBoardView()
                .tabItem { Label("Board", systemImage: "list.bullet.rectangle") }
                .tag(MainTab.board)

            BrainDumpView()
                .tabItem { Label("Brain Dump", systemImage: "text.badge.plus") }
                .tag(MainTab.brainDump)

            WeeklyCheckInView()
                .tabItem { Label("Check-In", systemImage: "clock.badge.checkmark") }
                .tag(MainTab.checkIn)

            PairingView()
                .tabItem { Label("Pair", systemImage: "person.2") }
                .tag(MainTab.pair)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .fairNestOpenWeeklyCheckIn)) { _ in
            openWeeklyCheckIn()
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: FairNestRouteRequest.openWeeklyCheckInOnLaunchKey) {
                openWeeklyCheckIn()
            }
        }
    }

    private func openWeeklyCheckIn() {
        UserDefaults.standard.removeObject(forKey: FairNestRouteRequest.openWeeklyCheckInOnLaunchKey)
        selection = .checkIn
    }
}

private enum MainTab: Hashable {
    case board
    case brainDump
    case checkIn
    case pair
    case settings
}
