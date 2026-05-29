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
    static let exportFailure = "FairNest couldn't prepare the export file. Check available storage and try again."
    static let clearExportFailure = "FairNest couldn't clear the temporary export file. Try again from this screen."
    static let localDeleteFailure = "FairNest couldn't delete all local data. Nothing was uploaded, and iCloud Sync remains off."
    static let sharedDeleteFailure = "FairNest couldn't finish deleting shared household data. Check iCloud and try again."

    static func boardOperationFailure(actionDescription: String) -> String {
        "FairNest couldn't \(actionDescription). Try again."
    }

    static func reminderSchedulingFailure(scheduleLabel: String) -> String {
        "Some reminders could not be scheduled. Weekly check-in is still set for \(scheduleLabel)."
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
