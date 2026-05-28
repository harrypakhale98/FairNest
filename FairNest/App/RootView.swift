import SwiftUI

struct RootView: View {
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
            if services.iCloudSyncEnabled {
                await services.pairingService.refresh()
            }
            await services.syncCardsIfAvailable()
        }
        .onChange(of: services.cardStore.cards) { _, cards in
            Task {
                await services.handleCardsChanged(cards)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fairNestAcceptedCloudKitShare)) { _ in
            services.pairingService.markShareAccepted()
            Task {
                await services.syncCardsIfAvailable()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fairNestFailedCloudKitShareAcceptance)) { notification in
            services.pairingService.markShareAcceptanceFailed(notification.object as? Error)
        }
        .onChange(of: services.iCloudSyncEnabled) { _, enabled in
            Task {
                if enabled {
                    await services.pairingService.refresh()
                }
                await services.syncCardsIfAvailable()
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeBoardView()
                .tabItem { Label("Board", systemImage: "list.bullet.rectangle") }

            BrainDumpView()
                .tabItem { Label("Brain Dump", systemImage: "text.badge.plus") }

            WeeklyCheckInView()
                .tabItem { Label("Check-In", systemImage: "clock.badge.checkmark") }

            PairingView()
                .tabItem { Label("Pair", systemImage: "person.2") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
