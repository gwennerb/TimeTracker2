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
    
    func exportText(for entries: [TimeEntry]) -> String {
        let monthEntries = entriesForMonth(entries)
        var lines: [String] = []
        
        lines.append("TimeTracker Summary - \(monthYearString)")
        lines.append("Total Hours: \(formattedHours(totalHoursForMonth(entries)))h")
        lines.append("")
        
        if monthEntries.isEmpty {
            lines.append("No entries logged for this month.")
            return lines.joined(separator: "\n")
        }
        
        lines.append("Category Totals:")
        for category in TaskCategory.allCases {
            let categoryHours = totalHoursForCategory(category, entries: entries)
            guard categoryHours > 0 else { continue }
            
            lines.append("- \(category.displayName): \(formattedHours(categoryHours))h")
            for item in taskHoursForCategory(category, entries: entries) {
                lines.append("  - \(item.task.name): \(formattedHours(item.hours))h")
            }
        }
        
        lines.append("")
        lines.append("Entries:")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let sortedEntries = monthEntries.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return (lhs.task?.name ?? "No Task").localizedCaseInsensitiveCompare(rhs.task?.name ?? "No Task") == .orderedAscending
        }
        
        for entry in sortedEntries {
            let taskName = entry.task?.name ?? "No Task"
            let categoryName = entry.task?.category.displayName ?? "Uncategorized"
            let notes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let notesText = notes.isEmpty ? "-" : notes.replacingOccurrences(of: "\n", with: " ")
            
            lines.append("- \(dateFormatter.string(from: entry.date)) | \(categoryName) | \(taskName) | \(formattedHours(entry.duration))h | Notes: \(notesText)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formattedHours(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
