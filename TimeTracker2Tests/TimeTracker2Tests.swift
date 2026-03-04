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
        
        let appTask = TrackedTask(name: "Feature Work", category: .app)
        let portalTask = TrackedTask(name: "Portal Support", category: .portal)
        
        let matchingEntries = [
            TimeEntry(
                date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))!,
                duration: 2.0,
                notes: "Shipped export",
                task: appTask
            ),
            TimeEntry(
                date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!,
                duration: 1.0,
                notes: "",
                task: portalTask
            )
        ]
        let nonMatchingEntry = TimeEntry(
            date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            duration: 9.0,
            notes: "Should be excluded",
            task: appTask
        )
        
        let text = viewModel.exportText(for: matchingEntries + [nonMatchingEntry])
        
        #expect(text.contains("TimeTracker Summary - \(viewModel.monthYearString)"))
        #expect(text.contains("Total Hours: 3.0h"))
        #expect(text.contains("Category Totals:"))
        #expect(text.contains("- App: 2.0h"))
        #expect(text.contains("- Portal: 1.0h"))
        #expect(text.contains("Entries:"))
        #expect(text.contains("- 2026-02-03 | App | Feature Work | 2.0h | Notes: Shipped export"))
        #expect(text.contains("- 2026-02-05 | Portal | Portal Support | 1.0h | Notes: -"))
        #expect(!text.contains("Should be excluded"))
    }
    
    @Test func summaryExportEmptyMonthShowsNoEntriesMessage() async throws {
        let viewModel = SummaryViewModel()
        let calendar = Calendar(identifier: .gregorian)
        viewModel.selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        
        let text = viewModel.exportText(for: [])
        
        #expect(text.contains("Total Hours: 0.0h"))
        #expect(text.contains("No entries logged for this month."))
    }

}
