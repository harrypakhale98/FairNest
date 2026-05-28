import CloudKit
import SwiftUI
import UIKit

struct PairingView: View {
    @EnvironmentObject private var pairingService: CloudKitPairingService
    @EnvironmentObject private var syncService: CloudKitSyncService
    @EnvironmentObject private var services: AppServices
    @State private var showingCloudSharing = false
    @State private var isCreatingInvite = false
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(pairingService.state.title, systemImage: symbol(for: pairingService.state))
                        .font(.headline)
                    Text(pairingService.state.message)
                        .foregroundStyle(.secondary)
                    if !services.iCloudSyncEnabled {
                        Text("Turn on iCloud Sync in Settings before creating or managing a partner invite.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Household sharing")
                }

                Section {
                    Button {
                        Task {
                            await syncService.refreshStatus()
                            await pairingService.refresh()
                        }
                    } label: {
                        Label("Refresh iCloud Status", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task {
                            isCreatingInvite = true
                            shareError = nil
                            await pairingService.createPrivateShare()
                            isCreatingInvite = false
                            if pairingService.currentShare != nil {
                                showingCloudSharing = true
                            } else if case .error(let message) = pairingService.state {
                                shareError = message
                            } else if pairingService.state != .partnerNotJoined {
                                shareError = pairingService.state.message
                            }
                        }
                    } label: {
                        Label(isCreatingInvite ? "Creating Invite" : "Create Partner Invite", systemImage: "person.badge.plus")
                    }
                    .disabled(!canCreateInvite || isCreatingInvite)

                    if isCreatingInvite {
                        ProgressView("Preparing iCloud invite")
                    }

                    if let shareError {
                        Label(shareError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }

                    if pairingService.currentShare != nil {
                        Button {
                            showingCloudSharing = true
                        } label: {
                            Label("Manage iCloud Share", systemImage: "person.2.badge.gearshape")
                        }
                    }

                }

                Section {
                    LabeledContent("Sync", value: syncService.status.label)
                    LabeledContent("Mode", value: pairingService.state == .paired ? "Shared" : "Solo-ready")
                } header: {
                    Text("Status")
                } footer: {
                    Text("FairNest has no accounts or passwords. Partner pairing uses private CloudKit Sharing and can be skipped. Invite and manage participants from the iCloud sharing sheet.")
                }
            }
            .navigationTitle("Pair")
            .sheet(isPresented: $showingCloudSharing) {
                if let share = pairingService.currentShare {
                    CloudSharingSheet(share: share) { error in
                        shareError = error.localizedDescription
                    }
                }
            }
        }
    }

    private var canCreateInvite: Bool {
        guard services.iCloudSyncEnabled else { return false }
        switch pairingService.state {
        case .checking, .iCloudUnavailable, .notSignedIn, .offline, .permissionDenied, .sharingRemoved, .syncPending:
            return false
        case .solo, .partnerNotJoined, .paired, .error:
            return true
        }
    }

    private func symbol(for state: PairingState) -> String {
        switch state {
        case .paired: return "person.2.fill"
        case .notSignedIn, .iCloudUnavailable, .permissionDenied, .sharingRemoved, .error: return "exclamationmark.icloud"
        case .offline, .syncPending: return "icloud.slash"
        default: return "person.2"
        }
    }
}

private struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    var onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: CloudKitSyncService.containerIdentifier))
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onError: (Error) -> Void

        init(onError: @escaping (Error) -> Void) {
            self.onError = onError
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "FairNest Household"
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onError(error)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}
