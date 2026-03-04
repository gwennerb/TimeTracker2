//
//  ReminderSettingsView.swift
//  TimeTracker2
//

import SwiftUI
import UserNotifications
import AppKit

struct ReminderSettingsView: View {
    @AppStorage(ReminderPreferences.enabledKey) private var isReminderEnabled = ReminderPreferences.defaultEnabled
    @AppStorage(ReminderPreferences.hourKey) private var reminderHour = ReminderPreferences.defaultHour
    @AppStorage(ReminderPreferences.minuteKey) private var reminderMinute = ReminderPreferences.defaultMinute

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Time Entry Reminder") {
                Toggle("Enable weekday reminders", isOn: $isReminderEnabled)

                DatePicker(
                    "Reminder time",
                    selection: reminderTimeBinding,
                    displayedComponents: [.hourAndMinute]
                )
                .disabled(!isReminderEnabled)

                Text("Reminders are scheduled Monday to Friday.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notification Access") {
                Text(authorizationDescription)
                    .foregroundStyle(.secondary)

                if authorizationStatus == .denied {
                    Button("Open Notification Settings") {
                        openNotificationSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 240)
        .task {
            await syncAndRefreshStatus()
        }
        .onChange(of: isReminderEnabled) { _, _ in
            Task { await syncAndRefreshStatus() }
        }
        .onChange(of: reminderHour) { _, _ in
            Task { await syncAndRefreshStatus() }
        }
        .onChange(of: reminderMinute) { _, _ in
            Task { await syncAndRefreshStatus() }
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let components = DateComponents(hour: reminderHour, minute: reminderMinute)
                if let date = calendar.date(from: components) {
                    return date
                }
                return calendar.date(from: DateComponents(
                    hour: ReminderPreferences.defaultHour,
                    minute: ReminderPreferences.defaultMinute
                )) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = components.hour ?? ReminderPreferences.defaultHour
                reminderMinute = components.minute ?? ReminderPreferences.defaultMinute
            }
        )
    }

    private var authorizationDescription: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Notifications are allowed."
        case .denied:
            return "Notifications are disabled for TimeTracker2."
        case .notDetermined:
            return "Notification permission will be requested when reminders are enabled."
        @unknown default:
            return "Notification status is unavailable."
        }
    }

    private func syncAndRefreshStatus() async {
        await ReminderScheduler.syncFromPreferences()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            authorizationStatus = settings.authorizationStatus
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    ReminderSettingsView()
}
