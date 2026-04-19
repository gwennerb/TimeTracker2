//
//  EntryDuplicator.swift
//  TimeTracker2
//

import Foundation
import SwiftData

enum EntryDuplicator {
    /// Copies all entries from `source` day to `target` day. Notes are not copied.
    /// Returns the inserted entries.
    @discardableResult
    static func duplicateDay(
        from source: Date,
        to target: Date,
        among entries: [TimeEntry],
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> [TimeEntry] {
        let sourceEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: source) }
        let targetDay = calendar.startOfDay(for: target)
        var inserted: [TimeEntry] = []
        for original in sourceEntries {
            guard let task = original.task, let project = original.project else { continue }
            let copy = TimeEntry(
                date: targetDay,
                duration: original.duration,
                notes: "",
                task: task,
                project: project
            )
            context.insert(copy)
            inserted.append(copy)
        }
        return inserted
    }

    /// For each day in the source week, duplicates entries to the matching weekday in the target week.
    /// Skips any (task, project, date) combo that already has an entry on the target day — never overwrites.
    @discardableResult
    static func duplicateWeek(
        from sourceWeekStart: Date,
        to targetWeekStart: Date,
        among entries: [TimeEntry],
        in context: ModelContext,
        calendar: Calendar = Calendars.iso8601Monday
    ) -> [TimeEntry] {
        let sourceStart = calendar.startOfDay(for: sourceWeekStart)
        let targetStart = calendar.startOfDay(for: targetWeekStart)
        var inserted: [TimeEntry] = []

        for offset in 0..<7 {
            guard let sourceDay = calendar.date(byAdding: .day, value: offset, to: sourceStart),
                  let targetDay = calendar.date(byAdding: .day, value: offset, to: targetStart) else { continue }

            let sourceEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: sourceDay) }
            let existingOnTarget = entries.filter { calendar.isDate($0.date, inSameDayAs: targetDay) }

            for original in sourceEntries {
                guard let task = original.task, let project = original.project else { continue }
                let alreadyHasIt = existingOnTarget.contains {
                    $0.task?.id == task.id && $0.project?.id == project.id
                }
                if alreadyHasIt { continue }

                let copy = TimeEntry(
                    date: calendar.startOfDay(for: targetDay),
                    duration: original.duration,
                    notes: "",
                    task: task,
                    project: project
                )
                context.insert(copy)
                inserted.append(copy)
            }
        }
        return inserted
    }

    /// Returns the most recent date strictly before `date` that has at least one entry, or nil.
    static func mostRecentPriorDay(
        before date: Date,
        in entries: [TimeEntry],
        calendar: Calendar = .current
    ) -> Date? {
        let cutoff = calendar.startOfDay(for: date)
        let earlier = entries
            .map { calendar.startOfDay(for: $0.date) }
            .filter { $0 < cutoff }
        return earlier.max()
    }
}
