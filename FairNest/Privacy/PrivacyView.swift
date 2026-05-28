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

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share Export File", systemImage: "doc")
                    }
                    Button(role: .destructive) {
                        clearExportFile()
                    } label: {
                        Label("Clear Export File", systemImage: "xmark.bin")
                    }
                    .accessibilityIdentifier("clearPrivacyExport")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Local Data", systemImage: "trash")
                }

                Button(role: .destructive) {
                    showingSharedDeleteConfirmation = true
                } label: {
                    Label("Delete Shared Household Data", systemImage: "trash.slash")
                }
                .disabled(syncService.status != .available)
                .accessibilityHint(sharedDeleteHint)

                if syncService.status != .available {
                    Text(sharedDeleteHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data controls")
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
            Text("This can remove iCloud household data where this account has permission. Export first if you need a copy.")
        }
    }

    private var privacyPolicyText: String {
        "FairNest stores household cards locally and only syncs through CloudKit when iCloud Sync is turned on. Weekly check-ins stay on this device and can be exported. FairNest has no ads, subscriptions, third-party analytics, or custom backend."
    }

    private var sharedDeleteHint: String {
        if syncService.status == .available {
            return "Deletes shared CloudKit household card data where this iCloud account has permission, then clears local data and reminders on this device."
        }
        return "Shared household deletion is available after iCloud is available. Current status: \(syncService.status.label)."
    }

    private func export() {
        do {
            exportURL = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportToTemporaryFile()
            message = "Export file is ready. Clear it from this screen when you are done sharing."
        } catch {
            message = error.localizedDescription
        }
    }

    private func clearExportFile() {
        if let exportURL {
            try? FileManager.default.removeItem(at: exportURL)
        }
        PrivacyExportService.removeTemporaryExports()
        exportURL = nil
        message = "Temporary export file cleared."
    }

    private func refreshPrivacyStatus() async {
        await syncService.refreshStatus()
        await pairingService.refresh()
    }

    private func deleteLocalData() async {
        do {
            try await services.deleteAllLocalDataForPrivacy()
            exportURL = nil
            message = "Local FairNest data, temporary exports, and scheduled reminders were deleted on this device. iCloud Sync is off."
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteSharedHouseholdData() async {
        do {
            try await services.deleteSharedHouseholdDataForPrivacy()
            exportURL = nil
            message = "Shared household data was deleted where this iCloud account has permission."
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct PrivacyPolicyDetailView: View {
    var body: some View {
        List {
            Section {
                Text("FairNest is a private household organization app. It does not sell data, show ads, use third-party analytics, use a custom server, or use paid APIs.")
                Text("Household cards, reminder settings, and pairing state are stored locally on device. iCloud Sync is off by default. When turned on, FairNest uses CloudKit to sync card data and private CloudKit Sharing to share a household with invited participants. Weekly check-ins stay on this device and can be exported.")
                Text("Brain dump parsing happens on device. When Apple Foundation Models are unavailable, FairNest uses a deterministic local parser. Raw brain dump text is never automatically shared.")
                Text("FairNest uses local notifications only after permission is granted. Users can export local data, delete local data and scheduled FairNest reminders from this device, and delete shared household data where their iCloud permissions allow it.")
            }
        }
        .navigationTitle("Privacy Policy")
    }
}
