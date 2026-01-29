//
//  SummaryViewModel.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import Foundation
import SwiftData

@Observable
final class SummaryViewModel {
    var selectedMonth: Date = Date()
    
    private let calendar = Calendar.current
    
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
    
    func entriesForMonth(_ entries: [TimeEntry]) -> [TimeEntry] {
        entries.filter { calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
    }
    
    func totalHoursForMonth(_ entries: [TimeEntry]) -> Double {
        entriesForMonth(entries).reduce(0) { $0 + $1.duration }
    }
    
    func entriesByCategory(_ entries: [TimeEntry]) -> [TaskCategory: [TimeEntry]] {
        let monthEntries = entriesForMonth(entries)
        var grouped: [TaskCategory: [TimeEntry]] = [:]
        
        for category in TaskCategory.allCases {
            let categoryEntries = monthEntries.filter { $0.task?.category == category }
            if !categoryEntries.isEmpty {
                grouped[category] = categoryEntries
            }
        }
        
        return grouped
    }
    
    func totalHoursForCategory(_ category: TaskCategory, entries: [TimeEntry]) -> Double {
        entriesByCategory(entries)[category]?.reduce(0) { $0 + $1.duration } ?? 0
    }
    
    func taskHoursForCategory(_ category: TaskCategory, entries: [TimeEntry]) -> [(task: TrackedTask, hours: Double)] {
        guard let categoryEntries = entriesByCategory(entries)[category] else { return [] }
        
        var taskHours: [String: (task: TrackedTask, hours: Double)] = [:]
        
        for entry in categoryEntries {
            guard let task = entry.task else { continue }
            let key = task.name
            if let existing = taskHours[key] {
                taskHours[key] = (task: existing.task, hours: existing.hours + entry.duration)
            } else {
                taskHours[key] = (task: task, hours: entry.duration)
            }
        }
        
        return taskHours.values.sorted { $0.hours > $1.hours }
    }
}
