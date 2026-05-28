import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var syncService: CloudKitSyncService
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingReminderIdentifiers: [String] = []
    @State private var notificationMessage: String?
    @State private var showingICloudSyncConfirmation = false
    @State private var showingReminderRemovalConfirmation = false
    @State private var cloudStatusRefreshInProgress = false
    @State private var notificationActionInProgress = false
    @State private var reminderRemovalInProgress = false

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
                    Toggle("Use iCloud Sync", isOn: iCloudSyncBinding)
                        .accessibilityIdentifier("settingsICloudSync")
                    if services.iCloudSyncEnabled {
                        LabeledContent("Status", value: syncService.status.label)
                        if let lastSyncMessage = services.lastSyncMessage {
                            Text(lastSyncMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await refreshCloudStatus() }
                        } label: {
                            Label("Refresh iCloud Status", systemImage: "arrow.clockwise")
                        }
                        .disabled(cloudStatusRefreshInProgress)
                    }
                    Text("Off by default. When on, FairNest syncs cards through the signed-in iCloud account and keeps check-ins local to this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Turning sync off stops future sync on this device. It does not delete iCloud data or end an existing household share.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("iCloud")
                }

                Section {
                    LabeledContent("Notifications", value: statusLabel)

                    if notificationStatus == .denied {
                        Button {
                            openAppSettings()
                        } label: {
                            Label("Open iOS Settings", systemImage: "gear")
                        }
                    } else {
                        Button {
                            Task { await requestNotifications() }
                        } label: {
                            Label(notificationActionTitle, systemImage: "bell")
                        }
                        .disabled(notificationActionInProgress)
                        .accessibilityIdentifier("settingsReminderAction")
                    }

                    if notificationsEnabled {
                        if hasWeeklyCheckInReminder {
                            Text("Weekly check-in: \(weeklyReminderScheduleLabel).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Weekly check-in is not scheduled.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Text(cardReminderSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if hasScheduledFairNestReminders {
                            Button(role: .destructive) {
                                showingReminderRemovalConfirmation = true
                            } label: {
                                Label("Remove All FairNest Reminders", systemImage: "bell.slash")
                            }
                            .disabled(reminderRemovalInProgress)
                            .accessibilityIdentifier("settingsRemoveAllReminders")
                        }

                        Text("Reminder alerts use private wording on the Lock Screen. Open FairNest to see card details.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if notificationActionInProgress || reminderRemovalInProgress {
                        Label("Updating reminders...", systemImage: "clock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
            .confirmationDialog(
                "Turn on iCloud Sync?",
                isPresented: $showingICloudSyncConfirmation,
                titleVisibility: .visible
            ) {
                Button("Turn On iCloud Sync") {
                    Task { await enableICloudSync() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing local cards will sync to iCloud. If this device joins a shared household, cards can be visible to invited participants. Weekly check-ins stay local.")
            }
            .confirmationDialog(
                "Remove all FairNest reminders?",
                isPresented: $showingReminderRemovalConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove All Reminders", role: .destructive) {
                    Task { await removeScheduledReminders() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes weekly check-in reminders and due-card reminders from this device. Notification permission itself is managed in iOS Settings.")
            }
            .task {
                await refreshSettingsState()
            }
            .refreshable {
                await refreshSettingsState()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshSettingsState() }
            }
            .onChange(of: services.iCloudSyncEnabled) { _, enabled in
                guard enabled else { return }
                Task { await refreshCloudStatus() }
            }
        }
    }

    private var iCloudSyncBinding: Binding<Bool> {
        Binding {
            services.iCloudSyncEnabled
        } set: { enabled in
            if enabled {
                showingICloudSyncConfirmation = true
            } else {
                services.iCloudSyncEnabled = false
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

    private var notificationsEnabled: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private var notificationActionTitle: String {
        guard notificationsEnabled else { return "Enable Gentle Reminders" }
        return hasWeeklyCheckInReminder ? "Reschedule Gentle Reminders" : "Schedule Gentle Reminders"
    }

    private var hasWeeklyCheckInReminder: Bool {
        pendingReminderIdentifiers.contains(ReminderRequestFactory.weeklyCheckInIdentifier)
    }

    private var dueCardReminderCount: Int {
        pendingReminderIdentifiers.filter(ReminderRequestFactory.isCardReminderIdentifier).count
    }

    private var hasScheduledFairNestReminders: Bool {
        !pendingReminderIdentifiers.isEmpty
    }

    private var cardReminderSummary: String {
        switch dueCardReminderCount {
        case 0:
            return "No due-card reminders are scheduled."
        case 1:
            return "1 due-card reminder is scheduled."
        default:
            return "\(dueCardReminderCount) due-card reminders are scheduled."
        }
    }

    private var weeklyReminderScheduleLabel: String {
        var components = DateComponents()
        components.weekday = Self.weeklyCheckInWeekday
        components.hour = Self.weeklyCheckInHour
        components.minute = Self.weeklyCheckInMinute
        let calendar = Calendar.current
        guard let date = calendar.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        ) else {
            return "Sunday, 6:00 PM"
        }
        return date.formatted(.dateTime.weekday(.wide).hour().minute())
    }

    private static let weeklyCheckInWeekday = 1
    private static let weeklyCheckInHour = 18
    private static let weeklyCheckInMinute = 0

    private func enableICloudSync() async {
        services.iCloudSyncEnabled = true
        await refreshCloudStatus()
    }

    private func refreshSettingsState() async {
        await refreshNotificationStatus()
        if services.iCloudSyncEnabled {
            await refreshCloudStatus()
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await services.reminderScheduler.authorizationStatus()
        pendingReminderIdentifiers = await services.reminderScheduler.pendingFairNestReminderIdentifiers()
    }

    private func refreshCloudStatus() async {
        guard !cloudStatusRefreshInProgress else { return }
        cloudStatusRefreshInProgress = true
        defer { cloudStatusRefreshInProgress = false }
        await syncService.refreshStatus()
    }

    private func requestNotifications() async {
        guard !notificationActionInProgress else { return }
        notificationActionInProgress = true
        defer { notificationActionInProgress = false }
        do {
            let allowed = try await services.reminderScheduler.requestAuthorization()
            if allowed {
                try await services.reminderScheduler.scheduleWeeklyCheckIn(
                    weekday: Self.weeklyCheckInWeekday,
                    hour: Self.weeklyCheckInHour,
                    minute: Self.weeklyCheckInMinute
                )
                try await services.scheduleRemindersForCurrentCards()
                notificationMessage = "Reminders are enabled. Weekly check-in is scheduled for \(weeklyReminderScheduleLabel)."
            } else {
                notificationMessage = "Reminders are off. You can change this in Settings."
            }
        } catch {
            notificationMessage = "Some reminders could not be scheduled: \(error.localizedDescription)"
        }
        await refreshNotificationStatus()
    }

    private func removeScheduledReminders() async {
        guard !reminderRemovalInProgress else { return }
        reminderRemovalInProgress = true
        defer { reminderRemovalInProgress = false }
        await services.reminderScheduler.cancelAllFairNestReminders()
        await refreshNotificationStatus()
        notificationMessage = "All scheduled FairNest reminders were removed."
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
        #endif
    }
}
