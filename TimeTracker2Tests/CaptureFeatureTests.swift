//
//  CaptureFeatureTests.swift
//  TimeTracker2Tests
//

import Testing
import Foundation
import SwiftData
@testable import TimeTracker2

@MainActor
struct CaptureFeatureTests {

    // MARK: - In-memory container helper

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TrackedTask.self, TimeEntry.self, Project.self, DayOff.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func calendar() -> Calendar { Calendar(identifier: .gregorian) }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar().date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - sortedByRecency

    @Test func sortedByRecencyPutsRecentlyUsedFirst() async throws {
        let oldFavorite = TrackedTask(name: "Old Favorite")
        let recentNewbie = TrackedTask(name: "Recent Newbie")

        let oldEntries = (1...10).map {
            TimeEntry(date: date(2026, 1, $0), duration: 1, task: oldFavorite, project: nil)
        }
        let recentEntry = TimeEntry(date: date(2026, 4, 15), duration: 1, task: recentNewbie, project: nil)

        oldFavorite.entries = oldEntries
        recentNewbie.entries = [recentEntry]

        let sorted = [oldFavorite, recentNewbie].sortedByRecency()
        #expect(sorted.first === recentNewbie)
        #expect(sorted.last === oldFavorite)
    }

    @Test func sortedByRecencyTieBreaksOnEntryCount() async throws {
        let busy = TrackedTask(name: "Busy")
        let quiet = TrackedTask(name: "Quiet")
        let sharedDate = date(2026, 4, 1)

        busy.entries = (0..<5).map { _ in TimeEntry(date: sharedDate, duration: 1, task: busy, project: nil) }
        quiet.entries = [TimeEntry(date: sharedDate, duration: 1, task: quiet, project: nil)]

        let sorted = [quiet, busy].sortedByRecency()
        #expect(sorted.first === busy)
    }

    // MARK: - EntryDuplicator.duplicateDay

    @Test func duplicateDayCopiesEntriesWithoutNotes() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let project = Project(name: "P")
        let task = TrackedTask(name: "T")
        context.insert(project)
        context.insert(task)

        let source = date(2026, 4, 1)
        let target = date(2026, 4, 2)

        let original = TimeEntry(date: source, duration: 3.5, notes: "first", task: task, project: project)
        let other = TimeEntry(date: source, duration: 1.0, notes: "second", task: task, project: project)
        context.insert(original)
        context.insert(other)

        let inserted = EntryDuplicator.duplicateDay(
            from: source, to: target,
            among: [original, other],
            in: context
        )

        #expect(inserted.count == 2)
        #expect(inserted.allSatisfy { $0.notes.isEmpty })
        #expect(inserted.contains { $0.duration == 3.5 })
        #expect(inserted.contains { $0.duration == 1.0 })
        #expect(inserted.allSatisfy { $0.task?.id == task.id })
        #expect(inserted.allSatisfy { $0.project?.id == project.id })
        let cal = Calendar.current
        #expect(inserted.allSatisfy { cal.isDate($0.date, inSameDayAs: target) })
    }

    @Test func duplicateDaySkipsEntriesMissingTaskOrProject() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TrackedTask(name: "T")
        context.insert(task)

        let source = date(2026, 4, 1)
        let target = date(2026, 4, 2)
        // Entry with nil project should be skipped
        let orphan = TimeEntry(date: source, duration: 1.0, notes: "orphan", task: task, project: nil)
        context.insert(orphan)

        let inserted = EntryDuplicator.duplicateDay(
            from: source, to: target,
            among: [orphan],
            in: context
        )
        #expect(inserted.isEmpty)
    }

    // MARK: - EntryDuplicator.duplicateWeek

    @Test func duplicateWeekSkipsCellsThatAlreadyHaveEntries() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let project = Project(name: "P")
        let taskA = TrackedTask(name: "A")
        let taskB = TrackedTask(name: "B")
        context.insert(project)
        context.insert(taskA)
        context.insert(taskB)

        // Source: Mon Apr 13 2026 (a Monday)
        let sourceMon = date(2026, 4, 13)
        let targetMon = date(2026, 4, 20)

        // Source has A on Mon, B on Tue
        let srcA = TimeEntry(date: sourceMon, duration: 8, task: taskA, project: project)
        let srcB = TimeEntry(date: date(2026, 4, 14), duration: 4, task: taskB, project: project)
        context.insert(srcA)
        context.insert(srcB)

        // Target already has A on Mon — should not get duplicated
        let preExisting = TimeEntry(date: targetMon, duration: 2, task: taskA, project: project)
        context.insert(preExisting)

        let allEntries = [srcA, srcB, preExisting]
        let inserted = EntryDuplicator.duplicateWeek(
            from: sourceMon, to: targetMon,
            among: allEntries,
            in: context
        )

        #expect(inserted.count == 1)
        #expect(inserted.first?.task?.id == taskB.id)
        #expect(inserted.first?.duration == 4)
    }

    // MARK: - mostRecentPriorDay

    @Test func mostRecentPriorDayPicksLatestBefore() async throws {
        let task = TrackedTask(name: "T")
        let project = Project(name: "P")
        let entries = [
            TimeEntry(date: date(2026, 4, 1), duration: 1, task: task, project: project),
            TimeEntry(date: date(2026, 4, 5), duration: 1, task: task, project: project),
            TimeEntry(date: date(2026, 4, 10), duration: 1, task: task, project: project),
        ]
        let result = EntryDuplicator.mostRecentPriorDay(
            before: date(2026, 4, 8),
            in: entries
        )
        let cal = Calendar.current
        #expect(result != nil && cal.isDate(result!, inSameDayAs: date(2026, 4, 5)))
    }

    @Test func mostRecentPriorDayReturnsNilWhenNoEarlierEntry() async throws {
        let task = TrackedTask(name: "T")
        let entries = [
            TimeEntry(date: date(2026, 4, 10), duration: 1, task: task, project: nil),
        ]
        let result = EntryDuplicator.mostRecentPriorDay(
            before: date(2026, 4, 1),
            in: entries
        )
        #expect(result == nil)
    }

    // MARK: - QuickEntryViewModel cell semantics

    @Test func quickEntryCellInsertsOnEmpty() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let project = Project(name: "P")
        let task = TrackedTask(name: "T")
        context.insert(project)
        context.insert(task)

        let vm = QuickEntryViewModel()
        vm.selectedProject = project

        let target = date(2026, 4, 13)
        let mutated = vm.commitCell(
            task: task, date: target, newValue: 4.0,
            currentState: .empty, in: context
        )
        #expect(mutated == true)

        try context.save()
        let inserted = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(inserted.count == 1)
        #expect(inserted.first?.duration == 4.0)
        #expect(inserted.first?.notes.isEmpty == true)
    }

    @Test func quickEntryCellUpdatesOnSingle() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let project = Project(name: "P")
        let task = TrackedTask(name: "T")
        context.insert(project)
        context.insert(task)
        let existing = TimeEntry(date: date(2026, 4, 13), duration: 2, task: task, project: project)
        context.insert(existing)

        let vm = QuickEntryViewModel()
        vm.selectedProject = project

        let mutated = vm.commitCell(
            task: task, date: date(2026, 4, 13), newValue: 6.0,
            currentState: .single(existing), in: context
        )
        #expect(mutated)
        #expect(existing.duration == 6.0)
    }

    @Test func quickEntryCellDeletesOnSingleZero() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let project = Project(name: "P")
        let task = TrackedTask(name: "T")
        context.insert(project)
        context.insert(task)
        let existing = TimeEntry(date: date(2026, 4, 13), duration: 2, task: task, project: project)
        context.insert(existing)

        let vm = QuickEntryViewModel()
        vm.selectedProject = project

        _ = vm.commitCell(
            task: task, date: date(2026, 4, 13), newValue: 0,
            currentState: .single(existing), in: context
        )
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(remaining.isEmpty)
    }

    @Test func quickEntryCellDoesNothingOnMulti() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let project = Project(name: "P")
        let task = TrackedTask(name: "T")
        context.insert(project)
        context.insert(task)

        let vm = QuickEntryViewModel()
        vm.selectedProject = project

        let mutated = vm.commitCell(
            task: task, date: date(2026, 4, 13), newValue: 5,
            currentState: .multi(count: 2, total: 4), in: context
        )
        #expect(mutated == false)
    }

    @Test func quickEntryCellStateSumsMultipleEntries() async throws {
        let project = Project(name: "P")
        let task = TrackedTask(name: "T")
        let day = date(2026, 4, 13)
        let entries = [
            TimeEntry(date: day, duration: 2, task: task, project: project),
            TimeEntry(date: day, duration: 3, task: task, project: project),
        ]

        let vm = QuickEntryViewModel()
        vm.selectedProject = project

        let state = vm.cellState(task: task, date: day, entries: entries)
        if case .multi(let count, let total) = state {
            #expect(count == 2)
            #expect(total == 5)
        } else {
            Issue.record("Expected multi cell state, got \(state)")
        }
    }

    // MARK: - Discord export

    @Test func discordExportWrapsTableInCodeFence() async throws {
        let vm = SummaryViewModel()
        vm.selectedMonth = date(2026, 2, 10)

        let app = TimeTracker2.Category(name: "App", colorName: "blue",
                                        iconSymbol: "app.fill", order: 0)
        let project = Project(name: "Acme")
        let task = TrackedTask(name: "Build", category: app)
        let entry = TimeEntry(date: date(2026, 2, 3), duration: 4, task: task, project: project)

        let text = vm.discordExportText(for: [entry], expectedHours: 160, categories: [app])
        #expect(text.contains("**TimeTracker — February 2026**"))
        #expect(text.contains("Total: 4.0h"))
        #expect(text.contains("Expected: 160.0h"))
        // Code fence
        #expect(text.contains("```"))
        // Project name appears in the table
        #expect(text.contains("Acme"))
        #expect(text.contains("TOTAL"))
    }

    @Test func discordExportProjectModeShowsTaskBreakdown() async throws {
        let vm = SummaryViewModel()
        vm.selectedMonth = date(2026, 2, 10)

        let app = TimeTracker2.Category(name: "App", colorName: "blue",
                                        iconSymbol: "app.fill", order: 0)
        let project = Project(name: "Acme")
        let frontend = TrackedTask(name: "Frontend", category: app)
        let backend = TrackedTask(name: "Backend", category: app)
        let entries = [
            TimeEntry(date: date(2026, 2, 3), duration: 6, task: frontend, project: project),
            TimeEntry(date: date(2026, 2, 4), duration: 2, task: backend, project: project),
        ]

        vm.selectedProject = project
        let text = vm.discordExportText(for: entries, expectedHours: 160, categories: [app])
        #expect(text.contains("**TimeTracker — February 2026 — Acme**"))
        #expect(text.contains("Frontend"))
        #expect(text.contains("Backend"))
        #expect(text.contains("Total: 8.0h"))
        #expect(!text.contains("Expected:"))  // expected line is all-projects only
    }

    @Test func discordExportEmptyMonthShowsEmptyMessage() async throws {
        let vm = SummaryViewModel()
        vm.selectedMonth = date(2026, 7, 1)

        let text = vm.discordExportText(for: [], expectedHours: 168, categories: [])
        #expect(text.contains("_No entries logged for this month._"))
    }
}
