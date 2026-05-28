import CloudKit
import Foundation

enum PairingState: Equatable {
    case solo
    case checking
    case iCloudUnavailable
    case notSignedIn
    case partnerNotJoined
    case syncPending
    case offline
    case permissionDenied
    case sharingRemoved
    case paired
    case error(String)

    var title: String {
        switch self {
        case .solo: return "Solo Mode"
        case .checking: return "Checking"
        case .iCloudUnavailable: return "iCloud Unavailable"
        case .notSignedIn: return "Sign in to iCloud"
        case .partnerNotJoined: return "Partner Not Joined"
        case .syncPending: return "Sync Pending"
        case .offline: return "Offline"
        case .permissionDenied: return "Permission Denied"
        case .sharingRemoved: return "Sharing Removed"
        case .paired: return "Partner Paired"
        case .error: return "Pairing Needs Attention"
        }
    }

    var message: String {
        switch self {
        case .solo:
            return "FairNest works privately on this iPhone. Pair later from this screen."
        case .checking:
            return "Checking iCloud sharing status."
        case .iCloudUnavailable:
            return "iCloud is not available right now. Local changes stay on this device."
        case .notSignedIn:
            return "Sign in to iCloud in Settings to sync and invite a partner."
        case .partnerNotJoined:
            return "The household share exists. Your partner has not joined yet."
        case .syncPending:
            return "Changes are saved locally and will sync when iCloud is ready."
        case .offline:
            return "You appear to be offline. FairNest will keep working locally."
        case .permissionDenied:
            return "FairNest does not have permission to access this shared household."
        case .sharingRemoved:
            return "The shared household was removed. You can continue in solo mode."
        case .paired:
            return "This household is shared through iCloud."
        case .error(let message):
            return message
        }
    }
}

@MainActor
protocol PairingService: AnyObject {
    var state: PairingState { get }
    var currentShare: CKShare? { get }
    func refresh() async
    func createPrivateShare() async
    func markShareAccepted()
}

@MainActor
final class CloudKitPairingService: ObservableObject, PairingService {
    @Published private(set) var state: PairingState = .solo
    @Published private(set) var currentShare: CKShare?

    private let containerProvider: () -> CKContainer

    init(containerProvider: @escaping () -> CKContainer = { CKContainer(identifier: CloudKitSyncService.containerIdentifier) }) {
        self.containerProvider = containerProvider
    }

    func refresh() async {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.arguments.contains("-disableCloudKit") {
            state = .iCloudUnavailable
            return
        }
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["FAIRNEST_ENABLE_CLOUDKIT"] == "1" else {
            state = .iCloudUnavailable
            return
        }
        #endif
        state = .checking
        do {
            let container = containerProvider()
            let account = try await container.accountStatus()
            switch account {
            case .available:
                let privateDatabase = container.privateCloudDatabase
                let sharedDatabase = container.sharedCloudDatabase
                let zoneID = CloudKitCardMapper.zoneID()
                if let share = try await existingZoneShare(in: privateDatabase, zoneID: zoneID) {
                    currentShare = share
                    state = .partnerNotJoined
                } else if try await hasAcceptedHouseholdShare(in: sharedDatabase) {
                    currentShare = nil
                    state = .paired
                } else {
                    currentShare = nil
                    state = .solo
                }
            case .noAccount:
                state = .notSignedIn
            case .restricted:
                state = .permissionDenied
            case .temporarilyUnavailable:
                state = .offline
            case .couldNotDetermine:
                state = .iCloudUnavailable
            @unknown default:
                state = .iCloudUnavailable
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func createPrivateShare() async {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["FAIRNEST_ENABLE_CLOUDKIT"] == "1" else {
            state = .iCloudUnavailable
            return
        }
        #endif
        state = .syncPending
        do {
            let container = containerProvider()
            let database = container.privateCloudDatabase
            let zoneID = CloudKitCardMapper.zoneID()
            try await CloudKitSyncService(containerProvider: containerProvider).ensureHouseholdZone(in: database)
            let share = try await existingZoneShare(in: database, zoneID: zoneID) ?? createZoneShare(zoneID: zoneID)
            share.publicPermission = .none
            _ = try await database.modifyRecords(
                saving: [share],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )
            currentShare = share
            state = .partnerNotJoined
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func markShareAccepted() {
        state = .paired
    }

    private func existingZoneShare(in database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await database.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func createZoneShare(zoneID: CKRecordZone.ID) -> CKShare {
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "FairNest Household" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.fairnest.household" as CKRecordValue
        share.publicPermission = .none
        return share
    }

    private func hasAcceptedHouseholdShare(in database: CKDatabase) async throws -> Bool {
        let zones = try await database.allRecordZones()
        return zones.contains { $0.zoneID.zoneName == CloudKitCardMapper.zoneName }
    }
}
