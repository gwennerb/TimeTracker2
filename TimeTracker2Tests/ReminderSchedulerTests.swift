//
//  ReminderSchedulerTests.swift
//  TimeTracker2Tests
//

import Testing
import Foundation
@testable import TimeTracker2

struct ReminderSchedulerTests {
    @Test func defaultsAreUsedWhenUnset() async throws {
        let suiteName = "ReminderSchedulerTests.defaults"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false))
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ReminderScheduler.isReminderEnabled(defaults: defaults))
        let components = ReminderScheduler.reminderTimeComponents(defaults: defaults)
        #expect(components.hour == 16)
        #expect(components.minute == 0)
    }

    @Test func storedValuesAndIdentifiersAreStable() async throws {
        let suiteName = "ReminderSchedulerTests.custom"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false))
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: ReminderPreferences.enabledKey)
        defaults.set(9, forKey: ReminderPreferences.hourKey)
        defaults.set(45, forKey: ReminderPreferences.minuteKey)

        #expect(ReminderScheduler.isReminderEnabled(defaults: defaults) == false)
        let components = ReminderScheduler.reminderTimeComponents(defaults: defaults)
        #expect(components.hour == 9)
        #expect(components.minute == 45)

        #expect(ReminderScheduler.weekdayNumbers == [2, 3, 4, 5, 6])
        let identifiers = ReminderScheduler.weekdayNumbers.map(ReminderScheduler.requestIdentifier)
        #expect(identifiers == [
            "weekday-reminder-2",
            "weekday-reminder-3",
            "weekday-reminder-4",
            "weekday-reminder-5",
            "weekday-reminder-6"
        ])
    }
}
