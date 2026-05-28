import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                }

                Section {
                    Toggle("Use iCloud Sync", isOn: $services.iCloudSyncEnabled)
                    Text("Off by default. When on, FairNest syncs cards through the signed-in iCloud account and keeps check-ins local to this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("iCloud")
                }

                Section {
                    LabeledContent("Notifications", value: statusLabel)

                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        Label("Enable Gentle Reminders", systemImage: "bell")
                    }

                    if let notificationMessage {
                        Text(notificationMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("FairNest uses local notifications only for due cards, recurring responsibilities, and weekly check-ins.")
                }

                Section {
                    LabeledContent("Price", value: "Free")
                    LabeledContent("Ads", value: "None")
                    LabeledContent("Subscriptions", value: "None")
                    LabeledContent("Backend", value: "iCloud only")
                } header: {
                    Text("App")
                }
            }
            .navigationTitle("Settings")
            .task {
                notificationStatus = await services.reminderScheduler.authorizationStatus()
            }
        }
    }

    private var statusLabel: String {
        switch notificationStatus {
        case .notDetermined: return "Not requested"
        case .denied: return "Off"
        case .authorized, .provisional, .ephemeral: return "On"
        @unknown default: return "Unknown"
        }
    }

    private func requestNotifications() async {
        do {
            let allowed = try await services.reminderScheduler.requestAuthorization()
            notificationStatus = await services.reminderScheduler.authorizationStatus()
            notificationMessage = allowed ? "Reminders are enabled." : "Reminders are off. You can change this in Settings."
            if allowed {
                try await services.reminderScheduler.scheduleWeeklyCheckIn(weekday: 1, hour: 18, minute: 0)
            }
        } catch {
            notificationMessage = error.localizedDescription
        }
    }
}
