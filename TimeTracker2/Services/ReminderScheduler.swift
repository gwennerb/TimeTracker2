//
//  ReminderScheduler.swift
//  TimeTracker2
//

import Foundation
import UserNotifications

enum ReminderPreferences {
    static let enabledKey = "reminder.enabled"
    static let hourKey = "reminder.hour"
    static let minuteKey = "reminder.minute"

    static let defaultEnabled = true
    static let defaultHour = 16
    static let defaultMinute = 0
}

enum ReminderScheduler {
    static let weekdayNumbers = Array(2...6) // Monday ... Friday

    static func isReminderEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: ReminderPreferences.enabledKey) as? Bool ?? ReminderPreferences.defaultEnabled
    }

    static func reminderTimeComponents(defaults: UserDefaults = .standard) -> DateComponents {
        let hour = defaults.object(forKey: ReminderPreferences.hourKey) as? Int ?? ReminderPreferences.defaultHour
        let minute = defaults.object(forKey: ReminderPreferences.minuteKey) as? Int ?? ReminderPreferences.defaultMinute
        return DateComponents(hour: hour, minute: minute)
    }

    static func requestIdentifier(for weekday: Int) -> String {
        "weekday-reminder-\(weekday)"
    }

    static func syncFromPreferences(
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) async {
        let identifiers = weekdayNumbers.map(requestIdentifier)
        guard isReminderEnabled(defaults: defaults) else {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            return
        }

        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    center.removePendingNotificationRequests(withIdentifiers: identifiers)
                    return
                }
            case .denied:
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
                return
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                print("Unknown notification authorization status.")
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
                return
            }

            center.removePendingNotificationRequests(withIdentifiers: identifiers)

            let time = reminderTimeComponents(defaults: defaults)
            let hour = time.hour ?? ReminderPreferences.defaultHour
            let minute = time.minute ?? ReminderPreferences.defaultMinute

            for weekday in weekdayNumbers {
                let request = makeRequest(weekday: weekday, hour: hour, minute: minute)
                try await add(request, center: center)
            }
        } catch {
            print("Failed to sync reminder notifications: \(error)")
        }
    }

    private static func makeRequest(weekday: Int, hour: Int, minute: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "TimeTracker Reminder"
        content.body = "Don't forget to log today's task entries."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar.current
        dateComponents.timeZone = .current
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        return UNNotificationRequest(
            identifier: requestIdentifier(for: weekday),
            content: content,
            trigger: trigger
        )
    }

    private static func add(_ request: UNNotificationRequest, center: UNUserNotificationCenter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
