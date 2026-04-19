//
//  QuickEntryViewModel.swift
//  TimeTracker2
//

import Foundation
import SwiftData

enum QuickEntryCellState: Equatable {
    case empty
    case single(TimeEntry)
    case multi(count: Int, total: Double)

    var displayHours: Double {
        switch self {
        case .empty: return 0
        case .single(let entry): return entry.duration
        case .multi(_, let total): return total
        }
    }

    var isEditable: Bool {
        if case .multi = self { return false }
        return true
    }
}

@Observable
final class QuickEntryViewModel {
    var weekStart: Date = QuickEntryViewModel.startOfCurrentWeek()
    var selectedProject: Project?

    private let calendar = Calendars.iso8601Monday

    static func startOfCurrentWeek() -> Date {
        let cal = Calendars.iso8601Monday
        let now = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: now)
        // Monday = 2 in this calendar
        let mondayBased = (weekday - 2 + 7) % 7
        return cal.date(byAdding: .day, value: -mondayBased, to: now) ?? now
    }

    var weekDates: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var weekRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        guard let last = weekDates.last else { return "" }
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: last)) \(yearFormatter.string(from: last))"
    }

    func previousWeek() {
        if let d = calendar.date(byAdding: .day, value: -7, to: weekStart) {
            weekStart = calendar.startOfDay(for: d)
        }
    }

    func nextWeek() {
        if let d = calendar.date(byAdding: .day, value: 7, to: weekStart) {
            weekStart = calendar.startOfDay(for: d)
        }
    }

    func goToCurrentWeek() {
        weekStart = Self.startOfCurrentWeek()
    }

    func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    /// Tasks to show as rows: active tasks plus any archived task that has an entry in this
    /// week+project (so historical data is visible). Sorted by recency.
    func taskRows(allTasks: [TrackedTask], entries: [TimeEntry]) -> [TrackedTask] {
        guard let project = selectedProject else { return [] }
        let weekEntries = entriesInWeek(entries: entries, project: project)
        let weekTaskIDs = Set(weekEntries.compactMap { $0.task?.id })

        var combined: [TrackedTask] = allTasks.filter { !$0.isArchived }
        for task in allTasks where task.isArchived && weekTaskIDs.contains(task.id) {
            if !combined.contains(where: { $0.id == task.id }) {
                combined.append(task)
            }
        }
        return combined.sortedByRecency()
    }

    func entriesInWeek(entries: [TimeEntry], project: Project) -> [TimeEntry] {
        guard let last = weekDates.last,
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: last) else {
            return []
        }
        let start = weekStart
        return entries.filter {
            $0.project?.id == project.id && $0.date >= start && $0.date < endExclusive
        }
    }

    func cellState(task: TrackedTask, date: Date, entries: [TimeEntry]) -> QuickEntryCellState {
        guard let project = selectedProject else { return .empty }
        let matching = entries.filter {
            $0.task?.id == task.id
                && $0.project?.id == project.id
                && calendar.isDate($0.date, inSameDayAs: date)
        }
        switch matching.count {
        case 0: return .empty
        case 1: return .single(matching[0])
        default:
            let total = matching.reduce(0.0) { $0 + $1.duration }
            return .multi(count: matching.count, total: total)
        }
    }

    /// Apply a typed value for a cell. Returns true if the model context was mutated.
    @discardableResult
    func commitCell(
        task: TrackedTask,
        date: Date,
        newValue: Double?,
        currentState: QuickEntryCellState,
        in context: ModelContext
    ) -> Bool {
        guard let project = selectedProject else { return false }
        let value = newValue ?? 0

        switch currentState {
        case .multi:
            return false
        case .empty:
            guard value > 0 else { return false }
            let entry = TimeEntry(
                date: calendar.startOfDay(for: date),
                duration: value,
                notes: "",
                task: task,
                project: project
            )
            context.insert(entry)
            return true
        case .single(let existing):
            if value <= 0 {
                context.delete(existing)
                return true
            }
            if existing.duration == value { return false }
            existing.duration = value
            return true
        }
    }

    func rowTotal(task: TrackedTask, entries: [TimeEntry]) -> Double {
        guard let project = selectedProject else { return 0 }
        return entries
            .filter {
                $0.task?.id == task.id
                    && $0.project?.id == project.id
                    && $0.date >= weekStart
                    && $0.date < (calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart)
            }
            .reduce(0.0) { $0 + $1.duration }
    }

    func columnTotal(date: Date, entries: [TimeEntry]) -> Double {
        guard let project = selectedProject else { return 0 }
        return entries
            .filter {
                $0.project?.id == project.id
                    && calendar.isDate($0.date, inSameDayAs: date)
            }
            .reduce(0.0) { $0 + $1.duration }
    }

    func weekTotal(entries: [TimeEntry]) -> Double {
        guard let project = selectedProject else { return 0 }
        return entriesInWeek(entries: entries, project: project)
            .reduce(0.0) { $0 + $1.duration }
    }

    func previousWeekStart() -> Date {
        calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
    }
}
