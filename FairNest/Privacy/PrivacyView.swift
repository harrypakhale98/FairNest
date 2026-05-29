import SwiftUI

struct PrivacyView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cardStore: LocalCardStore
    @EnvironmentObject private var checkInStore: LocalCheckInStore
    @EnvironmentObject private var syncService: CloudKitSyncService
    @EnvironmentObject private var pairingService: CloudKitPairingService
    @State private var exportURL: URL?
    @State private var showingDeleteConfirmation = false
    @State private var showingSharedDeleteConfirmation = false
    @State private var message: String?
    @State private var messageDetails: String?
    @State private var deletionOperation: PrivacyDeletionOperation?

    var body: some View {
        List {
            Section {
                LabeledContent("iCloud", value: syncService.status.label)
                LabeledContent("Partner sharing", value: pairingService.state.title)
                LabeledContent("Raw brain dumps", value: "Not auto-shared")
                LabeledContent("Analytics", value: "None")
            } header: {
                Text("Privacy status")
            }

            Section {
                Button {
                    export()
                } label: {
                    Label("Export Data", systemImage: "square.and.arrow.up")
                }
                .disabled(isDeleting)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share Export File", systemImage: "doc")
                    }
                    .disabled(isDeleting)

                    Button(role: .destructive) {
                        clearExportFile()
                    } label: {
                        Label("Clear Export File", systemImage: "xmark.bin")
                    }
                    .accessibilityIdentifier("clearPrivacyExport")
                    .disabled(isDeleting)
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label(localDeleteTitle, systemImage: localDeleteSymbol)
                }
                .disabled(isDeleting)

                Button(role: .destructive) {
                    showingSharedDeleteConfirmation = true
                } label: {
                    Label(sharedDeleteTitle, systemImage: sharedDeleteSymbol)
                }
                .disabled(syncService.status != .available || isDeleting)
                .accessibilityHint(sharedDeleteHint)

                if syncService.status != .available {
                    Text(sharedDeleteHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data controls")
            }

            if let deletionOperation {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(deletionOperation.progressMessage)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                Text(privacyPolicyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    PrivacyPolicyDetailView()
                } label: {
                    Label("Privacy Policy", systemImage: "doc.text")
                }
            } header: {
                Text("Policy summary")
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                    if let messageDetails {
                        TechnicalDetailsDisclosure(details: messageDetails)
                    }
                }
            }
        }
        .navigationTitle("Privacy")
        .task {
            await refreshPrivacyStatus()
        }
        .refreshable {
            await refreshPrivacyStatus()
        }
        .onDisappear {
            discardPreparedExportFile()
        }
        .confirmationDialog(
            "Delete all local FairNest data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Local Data", role: .destructive) {
                Task { await deleteLocalData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes cards, check-ins, temporary exports, and scheduled FairNest reminders from this device. iCloud Sync will be turned off so cloud data is not pulled back automatically.")
        }
        .confirmationDialog(
            "Delete shared household data?",
            isPresented: $showingSharedDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Shared Household Data", role: .destructive) {
                Task { await deleteSharedHouseholdData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes iCloud household cards where this account has permission, then clears local cards, check-ins, temporary exports, and scheduled FairNest reminders on this device. iCloud Sync will be turned off.")
        }
    }

    private var privacyPolicyText: String {
        PrivacyPolicyContent.summary
    }

    private var isDeleting: Bool {
        deletionOperation != nil
    }

    private var localDeleteTitle: String {
        deletionOperation == .local ? "Deleting Local Data" : "Delete Local Data"
    }

    private var localDeleteSymbol: String {
        deletionOperation == .local ? "hourglass" : "trash"
    }

    private var sharedDeleteTitle: String {
        deletionOperation == .shared ? "Deleting Shared Household Data" : "Delete Shared Household Data"
    }

    private var sharedDeleteSymbol: String {
        deletionOperation == .shared ? "hourglass" : "trash.slash"
    }

    private var sharedDeleteHint: String {
        if let deletionOperation {
            return deletionOperation.progressMessage
        }
        if syncService.status == .available {
            return "Deletes shared CloudKit household card data where this iCloud account has permission, then clears local data and reminders on this device."
        }
        return "Shared household deletion is available after iCloud is available. Current status: \(syncService.status.label)."
    }

    private func export() {
        do {
            exportURL = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportToTemporaryFile()
            message = "Export file is ready. Clear it from this screen when you are done sharing."
            messageDetails = nil
        } catch {
            message = FairNestIssueCopy.exportFailure
            messageDetails = error.localizedDescription
        }
    }

    private func clearExportFile() {
        do {
            try removePreparedExportFile()
            exportURL = nil
            message = "Temporary export file cleared."
            messageDetails = nil
        } catch {
            message = FairNestIssueCopy.clearExportFailure
            messageDetails = error.localizedDescription
        }
    }

    private func discardPreparedExportFile() {
        do {
            try removePreparedExportFile()
            exportURL = nil
        } catch {
            message = FairNestIssueCopy.clearExportFailure
            messageDetails = error.localizedDescription
        }
    }

    private func removePreparedExportFile() throws {
        if let exportURL, FileManager.default.fileExists(atPath: exportURL.path) {
            try FileManager.default.removeItem(at: exportURL)
        }
        try PrivacyExportService.removeTemporaryExports()
    }

    private func refreshPrivacyStatus() async {
        await syncService.refreshStatus()
        await pairingService.refresh()
    }

    private func deleteLocalData() async {
        guard deletionOperation == nil else { return }
        deletionOperation = .local
        defer { deletionOperation = nil }
        do {
            try await services.deleteAllLocalDataForPrivacy()
            exportURL = nil
            message = "Local FairNest data, temporary exports, and scheduled reminders were deleted on this device. iCloud Sync is off."
            messageDetails = nil
        } catch {
            message = FairNestIssueCopy.localDeleteFailure
            messageDetails = error.localizedDescription
        }
    }

    private func deleteSharedHouseholdData() async {
        guard deletionOperation == nil else { return }
        deletionOperation = .shared
        defer { deletionOperation = nil }
        do {
            try await services.deleteSharedHouseholdDataForPrivacy()
            exportURL = nil
            message = "Shared household data was deleted where this iCloud account has permission."
            messageDetails = nil
        } catch {
            message = FairNestIssueCopy.sharedDeleteFailure
            messageDetails = error.localizedDescription
        }
    }
}

private enum PrivacyDeletionOperation {
    case local
    case shared

    var progressMessage: String {
        switch self {
        case .local:
            return "Deleting local FairNest data, temporary exports, and reminders..."
        case .shared:
            return "Deleting shared household data, local data, temporary exports, and reminders..."
        }
    }
}

enum PrivacyPolicyContent {
    static let summary = "FairNest stores household cards locally and only syncs through CloudKit when iCloud Sync is turned on. Invited participants can see shared household cards. Removed cards use minimal deletion markers in local storage, iCloud, and exports. Weekly check-ins stay on this device and can be exported. FairNest has no ads, subscriptions, third-party analytics, or custom backend."

    static let fallbackMarkdown = """
    # FairNest Privacy Policy

    Last updated: May 28, 2026

    FairNest is a private household organization app. It does not sell data, show ads, use third-party analytics, use a custom server, or use paid APIs.

    Household cards, reminder settings, and pairing state are stored locally on device. iCloud Sync is off by default. When turned on, FairNest uses iCloud to sync card data and Apple's private sharing flow to share a household with invited participants. Invited participants can see shared household card data inside the private CloudKit share. Weekly check-ins stay on this device and can be exported.

    Brain dump suggestions are prepared on this iPhone. Raw brain dump text is never automatically shared.

    FairNest uses local notifications only after permission is granted. Users can export local data, delete local data and scheduled FairNest reminders from this device, and delete shared household data where their iCloud permissions allow it. Users can withdraw optional iCloud Sync by turning it off in Settings. Users can stop partner sharing or remove participants from the iCloud sharing sheet where their iCloud permissions allow it.

    Local FairNest data remains on the device until the user edits or deletes it, uses FairNest's deletion controls, deletes the app, or removes it through operating system storage controls. iCloud card data remains in the user's iCloud account and private CloudKit shares until removed by the user, a permitted share participant, FairNest's deletion controls, or Apple iCloud controls.

    When a card is removed, FairNest may keep a minimal deletion marker so that other devices know the card was removed. These markers omit the card title, notes, done criteria, due dates, recurrence, owner, and effort in local storage, iCloud sync records, and exported data.

    For support, email harry.pakhale98@gmail.com. Support email is optional and handled through the sender's and developer's email providers. Do not include private household card details unless they are needed to explain the issue.
    """

    static func bundledMarkdown(bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "PrivacyPolicy", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func markdown(bundle: Bundle = .main) -> String {
        bundledMarkdown(bundle: bundle) ?? fallbackMarkdown
    }

    static func attributedMarkdown(bundle: Bundle = .main) -> AttributedString {
        let text = markdown(bundle: bundle)
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct PrivacyPolicyDetailView: View {
    var body: some View {
        List {
            Section {
                Text(PrivacyPolicyContent.attributedMarkdown())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Privacy Policy")
    }
}
