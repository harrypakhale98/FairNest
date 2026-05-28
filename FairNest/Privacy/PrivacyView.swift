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
        .confirmationDialog(
            "Delete all local FairNest data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Local Data", role: .destructive) {
                PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).deleteAllLocalData()
                exportURL = nil
                message = "Local FairNest data was deleted on this device."
            }
            Button("Cancel", role: .cancel) {}
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

    private func export() {
        do {
            exportURL = try PrivacyExportService(cardStore: cardStore, checkInStore: checkInStore).exportToTemporaryFile()
            message = "Export file is ready."
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteSharedHouseholdData() async {
        do {
            try await syncService.deleteSharedHouseholdData()
            cardStore.deleteAllLocalData()
            checkInStore.deleteAll()
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
                Text("FairNest uses local notifications only after permission is granted. Users can export local data, delete local data, and delete shared household data where their iCloud permissions allow it.")
            }
        }
        .navigationTitle("Privacy Policy")
    }
}
