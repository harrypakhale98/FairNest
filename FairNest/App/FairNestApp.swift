import SwiftUI

@main
struct FairNestApp: App {
    @UIApplicationDelegateAdaptor(FairNestAppDelegate.self) private var appDelegate
    @StateObject private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services)
                .environmentObject(services.cardStore)
                .environmentObject(services.checkInStore)
                .environmentObject(services.syncService)
                .environmentObject(services.pairingService)
        }
    }
}
