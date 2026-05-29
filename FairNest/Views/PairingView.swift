import CloudKit
import SwiftUI
import UIKit

struct PairingView: View {
    @EnvironmentObject private var pairingService: CloudKitPairingService
    @EnvironmentObject private var syncService: CloudKitSyncService
    @EnvironmentObject private var services: AppServices
    @State private var showingCloudSharing = false
    @State private var showingICloudSyncConfirmation = false
    @State private var isCreatingInvite = false
    @State private var shareError: String?
    @State private var shareErrorDetails: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(pairingService.state.title, systemImage: symbol(for: pairingService.state))
                        .font(.headline)
                    Text(pairingService.state.message)
                        .foregroundStyle(.secondary)
                    if !services.iCloudSyncEnabled {
                        Text("Turn on iCloud Sync before creating or managing a partner invite.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Household sharing")
                }

                Section {
                    Button {
                        Task {
                            shareError = nil
                            shareErrorDetails = nil
                            await syncService.refreshStatus()
                            await pairingService.refresh()
                        }
                    } label: {
                        Label("Refresh iCloud Status", systemImage: "arrow.clockwise")
                    }

                    if !services.iCloudSyncEnabled {
                        Button {
                            showingICloudSyncConfirmation = true
                        } label: {
                            Label("Turn On iCloud Sync", systemImage: "icloud")
                        }
                    }

                    Button {
                        Task {
                            isCreatingInvite = true
                            shareError = nil
                            shareErrorDetails = nil
                            await pairingService.createPrivateShare()
                            isCreatingInvite = false
                            if pairingService.currentShare != nil {
                                showingCloudSharing = true
                            } else if case .error(let message) = pairingService.state {
                                shareError = FairNestIssueCopy.pairingFailure
                                shareErrorDetails = message
                            } else if pairingService.state != .partnerNotJoined {
                                shareError = pairingService.state.message
                            }
                        }
                    } label: {
                        Label(isCreatingInvite ? "Creating Invite" : "Create Partner Invite", systemImage: "person.badge.plus")
                    }
                    .disabled(!canCreateInvite || isCreatingInvite)
                    .accessibilityHint(inviteButtonAccessibilityHint)

                    if isCreatingInvite {
                        ProgressView("Preparing iCloud invite")
                    }

                    if let shareError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(shareError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            if let shareErrorDetails {
                                TechnicalDetailsDisclosure(details: shareErrorDetails)
                            }
                        }
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
                    LabeledContent("Mode", value: pairingService.state.modeLabel)
                    if pairingService.state == .paired {
                        Text("This iPhone is already part of a shared household. Manage participants from the iCloud sharing sheet when this device owns the share.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                } footer: {
                    Text("FairNest has no accounts or passwords. Partner pairing uses private CloudKit Sharing and can be skipped. Invite and manage participants from the iCloud sharing sheet.")
                }
            }
            .navigationTitle("Pair")
            .alert(
                "Turn on iCloud Sync?",
                isPresented: $showingICloudSyncConfirmation
            ) {
                Button("Turn On iCloud Sync") {
                    Task { await enableICloudSyncForPairing() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing local cards will sync to iCloud. If this device joins a shared household, cards can be visible to invited participants. Weekly check-ins stay local.")
            }
            .sheet(isPresented: $showingCloudSharing) {
                if let share = pairingService.currentShare {
                    CloudSharingSheet(share: share) { error in
                        shareError = FairNestIssueCopy.pairingFailure
                        shareErrorDetails = error.localizedDescription
                    } onStoppedSharing: {
                        pairingService.markSharingStopped()
                    }
                }
            }
        }
    }

    private var canCreateInvite: Bool {
        pairingService.state.allowsCreatingInvite(iCloudSyncEnabled: services.iCloudSyncEnabled)
    }

    private var inviteButtonAccessibilityHint: String {
        if isCreatingInvite {
            return "Wait for the iCloud invite to finish preparing."
        }
        guard services.iCloudSyncEnabled else {
            return "Turn on iCloud Sync before creating a partner invite."
        }
        if canCreateInvite {
            return "Creates a private iCloud share for this household."
        }
        switch pairingService.state {
        case .paired:
            return "This household is already shared. Manage participants from the iCloud sharing sheet."
        case .checking:
            return "Wait for FairNest to finish checking iCloud sharing status."
        default:
            return "Resolve the current iCloud sharing status before creating a partner invite."
        }
    }

    private func enableICloudSyncForPairing() async {
        shareError = nil
        shareErrorDetails = nil
        services.iCloudSyncEnabled = true
        await syncService.refreshStatus()
        await pairingService.refresh()
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
    var onError: @MainActor (Error) -> Void
    var onStoppedSharing: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError, onStoppedSharing: onStoppedSharing)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: CloudKitSyncService.containerIdentifier))
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onError: @MainActor (Error) -> Void
        let onStoppedSharing: @MainActor () -> Void

        init(onError: @escaping @MainActor (Error) -> Void, onStoppedSharing: @escaping @MainActor () -> Void) {
            self.onError = onError
            self.onStoppedSharing = onStoppedSharing
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "FairNest Household"
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in
                onError(error)
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                onStoppedSharing()
            }
        }
    }
}
