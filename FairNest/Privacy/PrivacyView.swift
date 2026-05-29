import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @AccessibilityFocusState private var resultFocused: Bool

    var body: some View {
        List {
            Section {
                LabeledContent("FairNest sync", value: services.iCloudSyncEnabled ? syncService.status.label : "iCloud Sync Off")
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
                .disabled(!canDeleteSharedHouseholdData)
                .accessibilityHint(sharedDeleteHint)

                if !canDeleteSharedHouseholdData {
                    Text(sharedDeleteHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data controls")
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("privacyResultMessage")
                        .accessibilityFocused($resultFocused)
                    if let messageDetails {
                        TechnicalDetailsDisclosure(details: messageDetails)
                    }
                }
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

    private var canDeleteSharedHouseholdData: Bool {
        syncService.status == .available && pairingService.state.allowsSharedHouseholdPrivacyDeletion && !isDeleting
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
        guard pairingService.state.allowsSharedHouseholdPrivacyDeletion else {
            return "Shared household deletion appears after this iPhone creates or joins a shared household."
        }
        if syncService.status == .available {
            return "Deletes shared CloudKit household card data where this iCloud account has permission, then clears local data and reminders on this device."
        }
        return "Shared household deletion is available after iCloud is available. Current status: \(syncService.status.label)."
    }

    private func export() {
        do {
            exportURL = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportToTemporaryFile()
            showResult("Export file is ready. Clear it from this screen when you are done sharing.")
        } catch {
            showResult(FairNestIssueCopy.exportFailure, details: error.localizedDescription)
        }
    }

    private func clearExportFile() {
        do {
            try removePreparedExportFile()
            exportURL = nil
            showResult("Temporary export file cleared.")
        } catch {
            showResult(FairNestIssueCopy.clearExportFailure, details: error.localizedDescription)
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
            showResult("Local FairNest data, temporary exports, and scheduled reminders were deleted on this device. iCloud Sync is off.")
        } catch {
            showResult(FairNestIssueCopy.localDeleteFailure, details: error.localizedDescription)
        }
    }

    private func deleteSharedHouseholdData() async {
        guard deletionOperation == nil else { return }
        deletionOperation = .shared
        defer { deletionOperation = nil }
        do {
            try await services.deleteSharedHouseholdDataForPrivacy()
            exportURL = nil
            showResult("Shared household data was deleted where this iCloud account has permission. Local FairNest data, temporary exports, and scheduled reminders were also deleted on this device. iCloud Sync is off.")
        } catch {
            showResult(FairNestIssueCopy.sharedDeleteFailureMessage(for: error), details: error.localizedDescription)
        }
    }

    private func showResult(_ newMessage: String, details: String? = nil) {
        message = newMessage
        messageDetails = details
        announce(newMessage)
        Task { @MainActor in
            await Task.yield()
            resultFocused = true
        }
    }

    private func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
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

    \(summary)

    For the complete policy, reinstall or update FairNest so the bundled privacy policy resource is available. For support, email harry.pakhale98@gmail.com.
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
