import CloudKit
import UIKit

extension Notification.Name {
    static let fairNestAcceptedCloudKitShare = Notification.Name("FairNestAcceptedCloudKitShare")
    static let fairNestFailedCloudKitShareAcceptance = Notification.Name("FairNestFailedCloudKitShareAcceptance")
}

final class FairNestAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task {
            do {
                let container = CKContainer(identifier: CloudKitSyncService.containerIdentifier)
                let results = try await container.accept([cloudKitShareMetadata])
                for result in results.values {
                    if case .failure(let error) = result {
                        NotificationCenter.default.post(
                            name: .fairNestFailedCloudKitShareAcceptance,
                            object: error
                        )
                        return
                    }
                }
                NotificationCenter.default.post(name: .fairNestAcceptedCloudKitShare, object: nil)
            } catch {
                NotificationCenter.default.post(
                    name: .fairNestFailedCloudKitShareAcceptance,
                    object: error
                )
            }
        }
    }
}
