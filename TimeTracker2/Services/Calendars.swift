//
//  Calendars.swift
//  TimeTracker2
//

import Foundation

enum Calendars {
    /// ISO 8601 calendar with Monday as the first weekday — matches the week math used in
    /// CalendarViewModel and SummaryViewModel.
    static var iso8601Monday: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }
}
