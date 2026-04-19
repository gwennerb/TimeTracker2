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
    var selectedProject: Project? = nil

    private let calendar = Calendar.current

    private var workCalendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }

    private static let hoursPerWorkday: Double = 8

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

    func scopedEntriesForMonth(_ entries: [TimeEntry]) -> [TimeEntry] {
        let monthEntries = entriesForMonth(entries)
        guard let project = selectedProject else { return monthEntries }
        return monthEntries.filter { $0.project?.id == project.id }
    }

    func totalHoursForMonth(_ entries: [TimeEntry]) -> Double {
        scopedEntriesForMonth(entries).reduce(0) { $0 + $1.duration }
    }

    func weekdaysInMonth() -> [Date] {
        let cal = workCalendar
        guard let interval = cal.dateInterval(of: .month, for: selectedMonth) else { return [] }
        var result: [Date] = []
        var current = interval.start
        while current < interval.end {
            let weekday = cal.component(.weekday, from: current)
            if weekday >= 2 && weekday <= 6 {
                result.append(current)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    func holidayWeekdaysInMonth() -> [Date] {
        weekdaysInMonth().filter { SwedishHolidays.holiday(for: $0, calendar: workCalendar) != nil }
    }

    func dayOffWeekdaysInMonth(_ daysOff: [DayOff]) -> [Date] {
        let cal = workCalendar
        return weekdaysInMonth().filter { date in
            guard SwedishHolidays.holiday(for: date, calendar: cal) == nil else { return false }
            return daysOff.contains { cal.isDate($0.date, inSameDayAs: date) }
        }
    }

    func expectedHoursForMonth(_ daysOff: [DayOff]) -> Double {
        let weekdays = weekdaysInMonth().count
        let holidays = holidayWeekdaysInMonth().count
        let offDays = dayOffWeekdaysInMonth(daysOff).count
        let workingDays = max(0, weekdays - holidays - offDays)
        return Double(workingDays) * Self.hoursPerWorkday
    }

    func dayOffHoursForMonth(_ daysOff: [DayOff]) -> Double {
        Double(dayOffWeekdaysInMonth(daysOff).count) * Self.hoursPerWorkday
    }

    func projectsWithEntriesInMonth(_ entries: [TimeEntry]) -> [Project] {
        let monthEntries = entriesForMonth(entries)
        var seen: Set<PersistentIdentifier> = []
        var ordered: [Project] = []
        for entry in monthEntries {
            guard let project = entry.project, !seen.contains(project.id) else { continue }
            seen.insert(project.id)
            ordered.append(project)
        }
        return ordered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func totalHoursForProject(_ project: Project, entries: [TimeEntry]) -> Double {
        entriesForMonth(entries)
            .filter { $0.project?.id == project.id }
            .reduce(0) { $0 + $1.duration }
    }

    func entriesByCategory(_ entries: [TimeEntry]) -> [TaskCategory: [TimeEntry]] {
        let scopedEntries = scopedEntriesForMonth(entries)
        var grouped: [TaskCategory: [TimeEntry]] = [:]

        for category in TaskCategory.allCases {
            let categoryEntries = scopedEntries.filter { $0.task?.category == category }
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
        if let project = selectedProject {
            return exportTextForProject(project, entries: entries)
        }
        return exportTextForAllProjects(entries: entries)
    }

    private func exportTextForAllProjects(entries: [TimeEntry]) -> String {
        let monthEntries = entriesForMonth(entries)
        var lines: [String] = []

        lines.append("TimeTracker Summary - \(monthYearString)")
        lines.append("Total Hours: \(formattedHours(monthEntries.reduce(0) { $0 + $1.duration }))h")
        lines.append("")

        if monthEntries.isEmpty {
            lines.append("No entries logged for this month.")
            return lines.joined(separator: "\n")
        }

        let projects = projectsWithEntriesInMonth(entries)
        let unassigned = monthEntries.filter { $0.project == nil }

        lines.append("Project Totals:")
        for project in projects {
            lines.append("- \(project.name): \(formattedHours(totalHoursForProject(project, entries: entries)))h")
        }
        if !unassigned.isEmpty {
            let unassignedHours = unassigned.reduce(0) { $0 + $1.duration }
            lines.append("- (Unassigned): \(formattedHours(unassignedHours))h")
        }
        lines.append("")

        for project in projects {
            lines.append(contentsOf: projectSection(project, entries: entries))
            lines.append("")
        }

        if !unassigned.isEmpty {
            lines.append(contentsOf: unassignedSection(unassigned: unassigned))
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func exportTextForProject(_ project: Project, entries: [TimeEntry]) -> String {
        var lines: [String] = []

        lines.append("TimeTracker Summary - \(monthYearString)")
        lines.append("Project: \(project.name)")
        lines.append("Total Hours: \(formattedHours(totalHoursForProject(project, entries: entries)))h")
        lines.append("")

        let projectEntries = entriesForMonth(entries).filter { $0.project?.id == project.id }
        if projectEntries.isEmpty {
            lines.append("No entries logged for this project this month.")
            return lines.joined(separator: "\n")
        }

        lines.append(contentsOf: projectSection(project, entries: entries, includeHeader: false))

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func projectSection(_ project: Project, entries: [TimeEntry], includeHeader: Bool = true) -> [String] {
        let previousSelection = selectedProject
        selectedProject = project
        defer { selectedProject = previousSelection }

        var lines: [String] = []
        if includeHeader {
            let total = totalHoursForProject(project, entries: entries)
            lines.append("=== \(project.name) — \(formattedHours(total))h ===")
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

        let projectEntries = entriesForMonth(entries).filter { $0.project?.id == project.id }
        let sorted = projectEntries.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return (lhs.task?.name ?? "No Task").localizedCaseInsensitiveCompare(rhs.task?.name ?? "No Task") == .orderedAscending
        }

        for entry in sorted {
            lines.append(formatEntryLine(entry, dateFormatter: dateFormatter))
        }

        return lines
    }

    private func unassignedSection(unassigned: [TimeEntry]) -> [String] {
        var lines: [String] = []
        let total = unassigned.reduce(0) { $0 + $1.duration }
        lines.append("=== (Unassigned) — \(formattedHours(total))h ===")
        lines.append("Entries:")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let sorted = unassigned.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return (lhs.task?.name ?? "No Task").localizedCaseInsensitiveCompare(rhs.task?.name ?? "No Task") == .orderedAscending
        }

        for entry in sorted {
            lines.append(formatEntryLine(entry, dateFormatter: dateFormatter))
        }

        return lines
    }

    private func formatEntryLine(_ entry: TimeEntry, dateFormatter: DateFormatter) -> String {
        let taskName = entry.task?.name ?? "No Task"
        let categoryName = entry.task?.category.displayName ?? "Uncategorized"
        let notes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesText = notes.isEmpty ? "-" : notes.replacingOccurrences(of: "\n", with: " ")

        return "- \(dateFormatter.string(from: entry.date)) | \(categoryName) | \(taskName) | \(formattedHours(entry.duration))h | Notes: \(notesText)"
    }

    private func formattedHours(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    func discordExportText(for entries: [TimeEntry], expectedHours: Double) -> String {
        if let project = selectedProject {
            return discordTextForProject(project, entries: entries)
        }
        return discordTextForAllProjects(entries: entries, expectedHours: expectedHours)
    }

    private func discordTextForAllProjects(entries: [TimeEntry], expectedHours: Double) -> String {
        let monthEntries = entriesForMonth(entries)
        let total = monthEntries.reduce(0.0) { $0 + $1.duration }

        var header: [String] = []
        header.append("**TimeTracker — \(monthYearString)**")
        header.append("Total: \(formattedHours(total))h  |  Expected: \(formattedHours(expectedHours))h")

        if monthEntries.isEmpty {
            header.append("_No entries logged for this month._")
            return header.joined(separator: "\n")
        }

        let projects = projectsWithEntriesInMonth(entries)
        let unassigned = monthEntries.filter { $0.project == nil }
        let unassignedHours = unassigned.reduce(0.0) { $0 + $1.duration }

        var rows: [(String, Double)] = projects.map { ($0.name, totalHoursForProject($0, entries: entries)) }
        if unassignedHours > 0 {
            rows.append(("(Unassigned)", unassignedHours))
        }

        let table = formatTwoColumnTable(
            headers: ("Project", "Hours"),
            rows: rows.map { ($0.0, formattedHours($0.1) + "h") },
            totalRow: ("TOTAL", formattedHours(total) + "h")
        )

        return (header + ["```", table, "```"]).joined(separator: "\n")
    }

    private func discordTextForProject(_ project: Project, entries: [TimeEntry]) -> String {
        let projectTotal = totalHoursForProject(project, entries: entries)
        var header: [String] = []
        header.append("**TimeTracker — \(monthYearString) — \(project.name)**")
        header.append("Total: \(formattedHours(projectTotal))h")

        let previousSelection = selectedProject
        selectedProject = project
        defer { selectedProject = previousSelection }

        var rows: [(category: String, task: String, hours: Double)] = []
        for category in TaskCategory.allCases {
            for item in taskHoursForCategory(category, entries: entries) {
                rows.append((category.displayName, item.task.name, item.hours))
            }
        }

        if rows.isEmpty {
            header.append("_No entries logged for this project this month._")
            return header.joined(separator: "\n")
        }

        let maxRows = 20
        var truncatedNote: String?
        if rows.count > maxRows {
            let kept = rows.prefix(maxRows)
            truncatedNote = "… and \(rows.count - maxRows) more rows"
            rows = Array(kept)
        }

        let table = formatThreeColumnTable(
            headers: ("Category", "Task", "Hours"),
            rows: rows.map { ($0.category, $0.task, formattedHours($0.hours) + "h") },
            totalRow: ("TOTAL", "", formattedHours(projectTotal) + "h"),
            footer: truncatedNote
        )

        return (header + ["```", table, "```"]).joined(separator: "\n")
    }

    private func formatTwoColumnTable(
        headers: (String, String),
        rows: [(String, String)],
        totalRow: (String, String)
    ) -> String {
        let allLeft = [headers.0] + rows.map { $0.0 } + [totalRow.0]
        let allRight = [headers.1] + rows.map { $0.1 } + [totalRow.1]
        let leftWidth = allLeft.map { $0.count }.max() ?? 0
        let rightWidth = allRight.map { $0.count }.max() ?? 0
        let totalWidth = leftWidth + 2 + rightWidth
        let divider = String(repeating: "─", count: totalWidth)

        var lines: [String] = []
        lines.append(padRight(headers.0, leftWidth) + "  " + padLeft(headers.1, rightWidth))
        lines.append(divider)
        for row in rows {
            lines.append(padRight(row.0, leftWidth) + "  " + padLeft(row.1, rightWidth))
        }
        lines.append(divider)
        lines.append(padRight(totalRow.0, leftWidth) + "  " + padLeft(totalRow.1, rightWidth))
        return lines.joined(separator: "\n")
    }

    private func formatThreeColumnTable(
        headers: (String, String, String),
        rows: [(String, String, String)],
        totalRow: (String, String, String),
        footer: String?
    ) -> String {
        let allCol1 = [headers.0] + rows.map { $0.0 } + [totalRow.0]
        let allCol2 = [headers.1] + rows.map { $0.1 } + [totalRow.1]
        let allCol3 = [headers.2] + rows.map { $0.2 } + [totalRow.2]
        let w1 = allCol1.map { $0.count }.max() ?? 0
        let w2 = allCol2.map { $0.count }.max() ?? 0
        let w3 = allCol3.map { $0.count }.max() ?? 0
        let totalWidth = w1 + 2 + w2 + 2 + w3
        let divider = String(repeating: "─", count: totalWidth)

        var lines: [String] = []
        lines.append(padRight(headers.0, w1) + "  " + padRight(headers.1, w2) + "  " + padLeft(headers.2, w3))
        lines.append(divider)
        for row in rows {
            lines.append(padRight(row.0, w1) + "  " + padRight(row.1, w2) + "  " + padLeft(row.2, w3))
        }
        lines.append(divider)
        lines.append(padRight(totalRow.0, w1) + "  " + padRight(totalRow.1, w2) + "  " + padLeft(totalRow.2, w3))
        if let footer {
            lines.append(footer)
        }
        return lines.joined(separator: "\n")
    }

    private func padRight(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private func padLeft(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}
