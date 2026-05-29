import CloudKit
import UIKit
import UserNotifications

extension Notification.Name {
    static let fairNestAcceptedCloudKitShare = Notification.Name("FairNestAcceptedCloudKitShare")
    static let fairNestFailedCloudKitShareAcceptance = Notification.Name("FairNestFailedCloudKitShareAcceptance")
    static let fairNestOpenBrainDump = Notification.Name("FairNestOpenBrainDump")
    static let fairNestOpenWeeklyCheckIn = Notification.Name("FairNestOpenWeeklyCheckIn")
}

enum FairNestRouteRequest {
    static let openWeeklyCheckInOnLaunchKey = "FairNestOpenWeeklyCheckInOnLaunch"
    static let pendingAcceptedCloudKitShareKey = "FairNestPendingAcceptedCloudKitShare"
}

final class FairNestAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task {
            do {
                let container = CKContainer(identifier: CloudKitSyncService.containerIdentifier)
                let results = try await container.accept([cloudKitShareMetadata])
                for result in results.values {
                    switch result {
                    case .success(let share):
                        CloudKitHouseholdSelection.rememberSharedZoneID(share.recordID.zoneID)
                    case .failure(let error):
                        NotificationCenter.default.post(
                            name: .fairNestFailedCloudKitShareAcceptance,
                            object: error
                        )
                        return
                    }
                }
                UserDefaults.standard.set(true, forKey: FairNestRouteRequest.pendingAcceptedCloudKitShareKey)
                NotificationCenter.default.post(name: .fairNestAcceptedCloudKitShare, object: nil)
            } catch {
                NotificationCenter.default.post(
                    name: .fairNestFailedCloudKitShareAcceptance,
                    object: error
                )
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == ReminderRequestFactory.weeklyCheckInIdentifier {
            UserDefaults.standard.set(true, forKey: FairNestRouteRequest.openWeeklyCheckInOnLaunchKey)
            NotificationCenter.default.post(name: .fairNestOpenWeeklyCheckIn, object: nil)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
