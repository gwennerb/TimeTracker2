//
//  CalendarViewModel.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
final class CalendarViewModel {
    var selectedDate: Date = Date()
    var selectedMonth: Date = Date()
    var showingEntrySheet: Bool = false
    var selectedDayForEntry: Date?
    
    private var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday = 2
        return cal
    }
    
    var currentMonthDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth) else {
            return []
        }
        
        // Find the Monday before or on the first day of the month
        let firstDayOfMonth = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstDayOfMonth)
        // Convert to Monday-based: Monday=0, Tuesday=1, ..., Sunday=6
        let mondayBasedWeekday = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -mondayBasedWeekday, to: firstDayOfMonth)!
        
        // Find the last day of the month and extend to Sunday
        let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end)!
        let lastWeekday = calendar.component(.weekday, from: lastDayOfMonth)
        let lastMondayBasedWeekday = (lastWeekday + 5) % 7
        let daysToAdd = 6 - lastMondayBasedWeekday
        let end = calendar.date(byAdding: .day, value: daysToAdd + 1, to: lastDayOfMonth)!
        
        var dates: [Date] = []
        var current = start
        while current < end {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return dates
    }
    
    var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }
    
    func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }
    
    func isCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: selectedMonth, toGranularity: .month)
    }
    
    func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    func selectDay(_ date: Date) {
        selectedDayForEntry = date
        showingEntrySheet = true
    }
    
    func entriesForDate(_ date: Date, entries: [TimeEntry]) -> [TimeEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    func totalHoursForDate(_ date: Date, entries: [TimeEntry]) -> Double {
        entriesForDate(date, entries: entries).reduce(0) { $0 + $1.duration }
    }
    
    func isIncompleteWeekday(_ date: Date, totalHours: Double) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        // Sunday = 1, Saturday = 7
        guard weekday >= 2 && weekday <= 6 else { return false }
        guard calendar.isDateInToday(date) || date < calendar.startOfDay(for: Date()) else { return false }
        return totalHours < 8
    }

    func categoriesForDate(_ date: Date, entries: [TimeEntry]) -> Set<TaskCategory> {
        let dayEntries = entriesForDate(date, entries: entries)
        return Set(dayEntries.compactMap { $0.task?.category })
    }
}
