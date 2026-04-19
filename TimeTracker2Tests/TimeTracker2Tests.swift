//
//  TimeTracker2Tests.swift
//  TimeTracker2Tests
//
//  Created by Per Bergström on 2025-12-06.
//

import Testing
import Foundation
@testable import TimeTracker2

struct TimeTracker2Tests {

    @Test func summaryExportIncludesTotalsAndEntries() async throws {
        let viewModel = SummaryViewModel()
        let calendar = Calendar(identifier: .gregorian)
        viewModel.selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!

        let project = Project(name: "Varberg")
        let appTask = TrackedTask(name: "Feature Work", category: .app)
        let portalTask = TrackedTask(name: "Portal Support", category: .portal)

        let matchingEntries = [
            TimeEntry(
                date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))!,
                duration: 2.0,
                notes: "Shipped export",
                task: appTask,
                project: project
            ),
            TimeEntry(
                date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!,
                duration: 1.0,
                notes: "",
                task: portalTask,
                project: project
            )
        ]
        let nonMatchingEntry = TimeEntry(
            date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            duration: 9.0,
            notes: "Should be excluded",
            task: appTask,
            project: project
        )

        let text = viewModel.exportText(for: matchingEntries + [nonMatchingEntry])

        #expect(text.contains("TimeTracker Summary - \(viewModel.monthYearString)"))
        #expect(text.contains("Total Hours: 3.0h"))
        #expect(text.contains("Project Totals:"))
        #expect(text.contains("- Varberg: 3.0h"))
        #expect(text.contains("=== Varberg — 3.0h ==="))
        #expect(text.contains("Category Totals:"))
        #expect(text.contains("- App: 2.0h"))
        #expect(text.contains("- Portal: 1.0h"))
        #expect(text.contains("Entries:"))
        #expect(text.contains("- 2026-02-03 | App | Feature Work | 2.0h | Notes: Shipped export"))
        #expect(text.contains("- 2026-02-05 | Portal | Portal Support | 1.0h | Notes: -"))
        #expect(!text.contains("Should be excluded"))
    }

    @Test func summaryExportForSelectedProjectShowsOnlyThatProject() async throws {
        let viewModel = SummaryViewModel()
        let calendar = Calendar(identifier: .gregorian)
        viewModel.selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!

        let varberg = Project(name: "Varberg")
        let acme = Project(name: "Acme")
        let task = TrackedTask(name: "Feature Work", category: .app)

        let entries = [
            TimeEntry(
                date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))!,
                duration: 2.0,
                notes: "Varberg work",
                task: task,
                project: varberg
            ),
            TimeEntry(
                date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 4))!,
                duration: 3.0,
                notes: "Acme work",
                task: task,
                project: acme
            )
        ]

        viewModel.selectedProject = varberg
        let text = viewModel.exportText(for: entries)

        #expect(text.contains("Project: Varberg"))
        #expect(text.contains("Total Hours: 2.0h"))
        #expect(text.contains("Varberg work"))
        #expect(!text.contains("Acme work"))
        #expect(!text.contains("Project Totals:"))
    }
    
    @Test func summaryExportEmptyMonthShowsNoEntriesMessage() async throws {
        let viewModel = SummaryViewModel()
        let calendar = Calendar(identifier: .gregorian)
        viewModel.selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!

        let text = viewModel.exportText(for: [])

        #expect(text.contains("Total Hours: 0.0h"))
        #expect(text.contains("No entries logged for this month."))
    }

    @Test func swedishHolidaysEasterDerivedFor2026() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let goodFriday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 3))!
        let easterMonday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 6))!
        let ascension = calendar.date(from: DateComponents(year: 2026, month: 5, day: 14))!

        #expect(SwedishHolidays.holiday(for: goodFriday, calendar: calendar)?.name == "Långfredagen")
        #expect(SwedishHolidays.holiday(for: easterMonday, calendar: calendar)?.name == "Annandag påsk")
        #expect(SwedishHolidays.holiday(for: ascension, calendar: calendar)?.name == "Kristi himmelsfärdsdag")
    }

    @Test func swedishHolidaysFixedDates() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let nyarsdagen = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let nationaldag = calendar.date(from: DateComponents(year: 2026, month: 6, day: 6))!
        let julafton = calendar.date(from: DateComponents(year: 2026, month: 12, day: 24))!
        let nyarsafton = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!

        #expect(SwedishHolidays.holiday(for: nyarsdagen, calendar: calendar)?.name == "Nyårsdagen")
        #expect(SwedishHolidays.holiday(for: nationaldag, calendar: calendar)?.name == "Sveriges nationaldag")
        #expect(SwedishHolidays.holiday(for: julafton, calendar: calendar)?.name == "Julafton")
        #expect(SwedishHolidays.holiday(for: nyarsafton, calendar: calendar)?.name == "Nyårsafton")
    }

    @Test func swedishHolidaysMidsommarafton2026() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let midsommarafton = calendar.date(from: DateComponents(year: 2026, month: 6, day: 19))!
        let dayBefore = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!

        #expect(SwedishHolidays.holiday(for: midsommarafton, calendar: calendar)?.name == "Midsommarafton")
        #expect(SwedishHolidays.holiday(for: dayBefore, calendar: calendar) == nil)
    }

    @Test func swedishHolidaysNonHolidayReturnsNil() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let regular = calendar.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        #expect(SwedishHolidays.holiday(for: regular, calendar: calendar) == nil)
    }

    @Test func expectedHoursExcludesHolidaysAndDayOffs() async throws {
        let viewModel = SummaryViewModel()
        let calendar = Calendar(identifier: .gregorian)
        viewModel.selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!

        // December 2026: 23 weekdays total. Weekday holidays: Dec 24 (Thu, Julafton),
        // Dec 25 (Fri, Juldagen), Dec 31 (Thu, Nyårsafton). => 20 working days × 8h = 160h.
        let expected = viewModel.expectedHoursForMonth([])
        #expect(expected == 160)

        let offDate = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        let withDayOff = viewModel.expectedHoursForMonth([DayOff(date: offDate)])
        #expect(withDayOff == 152)
        #expect(viewModel.dayOffHoursForMonth([DayOff(date: offDate)]) == 8)
    }

    @Test func dayOffOnHolidayDoesNotDoubleCount() async throws {
        let viewModel = SummaryViewModel()
        let calendar = Calendar(identifier: .gregorian)
        viewModel.selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!

        let julafton = calendar.date(from: DateComponents(year: 2026, month: 12, day: 24))!
        let expected = viewModel.expectedHoursForMonth([DayOff(date: julafton)])
        #expect(expected == 160)
        #expect(viewModel.dayOffHoursForMonth([DayOff(date: julafton)]) == 0)
    }

}
