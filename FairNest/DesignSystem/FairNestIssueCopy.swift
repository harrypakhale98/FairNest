import Foundation
import SwiftUI

enum FairNestIssueCopy {
    static let localCardLoadFailure = "FairNest moved an unreadable card file aside so the board can keep working."
    static let localCardReadUnavailable = "FairNest couldn't read the local card file. Close and reopen FairNest after unlocking this iPhone, then try again."
    static let localCardSaveFailure = "FairNest couldn't save the latest board change. Keep FairNest open and try again before closing the app."
    static let localCheckInLoadFailure = "FairNest moved an unreadable check-in file aside so check-ins can keep working."
    static let localCheckInReadUnavailable = "FairNest couldn't read previous check-ins. Close and reopen FairNest after unlocking this iPhone, then try again."
    static let localCheckInSaveFailure = "FairNest couldn't save this check-in. Keep FairNest open and try again before closing the app."
    static let brainDumpParseFailure = "FairNest couldn't turn that text into cards. Edit the brain dump and try again."
    static let brainDumpSaveFailure = "FairNest couldn't save those cards. Your brain dump is still here."
    static let syncDelay = "FairNest is keeping changes on this iPhone and will try iCloud again."
    static let reminderUpdateFailure = "FairNest couldn't update every reminder. Your cards are still saved."
    static let pairingFailure = "FairNest couldn't finish the iCloud pairing step. Check iCloud and try again."
    static let invalidCardStatusTransition = "That card cannot move directly to the selected status. Choose one of the available status options."
    static let exportFailure = "FairNest couldn't prepare the export file. Check available storage and try again."
    static let clearExportFailure = "FairNest couldn't clear the temporary export file. Try again from this screen."
    static let localDeleteFailure = "FairNest couldn't finish deleting all local data. Your previous iCloud Sync setting was restored; check details before trying again."
    static let sharedDeleteFailure = "Local data was deleted on this device, but FairNest couldn't finish deleting shared household data in iCloud. iCloud Sync remains off."
    static let sharedDeleteSelectionFailure = "FairNest couldn't choose which shared household to delete. Local data was kept on this device, and iCloud Sync is off so old cards are not uploaded again."
    static let sharedDeleteCloudFailure = "Local data was deleted on this device, but FairNest couldn't finish deleting shared household data in iCloud. iCloud Sync remains off."
    static let sharedDeleteLocalFailure = "FairNest couldn't finish deleting local data after the shared iCloud deletion step. iCloud Sync remains off so old cards are not uploaded again."
    static let sharedDeleteCloudAndLocalFailure = "FairNest couldn't finish deleting shared iCloud data or local device data. iCloud Sync remains off so old cards are not uploaded again."
    static let sharedHouseholdErased = "Shared household data was erased from iCloud. FairNest turned sync off on this iPhone so old cards are not uploaded again."
    static let sharedHouseholdUnavailable = "FairNest lost access to the shared household in iCloud. Sync was turned off on this iPhone so old shared cards are not uploaded again."
    static let iCloudAccountChanged = "The signed-in iCloud account changed. FairNest turned sync off before uploading local cards to the new iCloud account."

    static func boardOperationFailure(actionDescription: String) -> String {
        "FairNest couldn't \(actionDescription). Try again."
    }

    static func reminderSchedulingFailure(scheduleLabel: String) -> String {
        "FairNest couldn't update every reminder. Your cards are still saved. Try again from Settings; the weekly check-in target is \(scheduleLabel)."
    }

    static func sharedDeleteFailureMessage(for error: Error) -> String {
        if error as? CloudKitHouseholdSelectionError == .ambiguousSharedHouseholdDeletion {
            return sharedDeleteSelectionFailure
        }
        if let deletionError = error as? PrivacyDeletionError {
            switch deletionError {
            case .sharedAndLocalDeletionFailed:
                return sharedDeleteCloudAndLocalFailure
            case .localDeletionFailedAfterSharedDeletion:
                return sharedDeleteLocalFailure
            }
        }
        return sharedDeleteCloudFailure
    }
}

struct TechnicalDetailsDisclosure: View {
    var details: String

    var body: some View {
        DisclosureGroup("Technical Detail") {
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("technicalDetailsDisclosure")
    }
}
