//
//  CategoryMigrationTests.swift
//  TimeTracker2Tests
//

import Testing
import SwiftData
import Foundation
@testable import TimeTracker2

struct CategoryMigrationTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TimeTracker2.Category.self, TrackedTask.self, TimeEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test @MainActor
    func freshInstallSeedsFourCategoriesInOrder() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        CategoryMigration.run(in: context)

        let descriptor = FetchDescriptor<TimeTracker2.Category>(sortBy: [SortDescriptor(\TimeTracker2.Category.order)])
        let categories = try context.fetch(descriptor)
        #expect(categories.count == 4)
        #expect(categories.map(\.name) == ["App", "Portal", "Back Office", "Misc"])
        #expect(categories.map(\.colorName) == ["blue", "purple", "orange", "gray"])
        #expect(categories.map(\.iconSymbol) == ["app.fill", "globe", "building.2.fill", "ellipsis.circle.fill"])
        #expect(categories.map(\.order) == [0, 1, 2, 3])
        #expect(categories.allSatisfy { !$0.isArchived })
    }

    @Test @MainActor
    func existingTasksLinkToMatchingSeedByName() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let appTask = TrackedTask(name: "Feature", legacyCategoryRawValue: "App")
        let portalTask = TrackedTask(name: "Reset password", legacyCategoryRawValue: "Portal")
        context.insert(appTask)
        context.insert(portalTask)
        try context.save()

        CategoryMigration.run(in: context)

        #expect(appTask.category?.name == "App")
        #expect(portalTask.category?.name == "Portal")
    }

    @Test @MainActor
    func unrecognisedCategoryRawValueFallsBackToMisc() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TrackedTask(name: "Mystery", legacyCategoryRawValue: "Bogus")
        context.insert(task)
        try context.save()

        CategoryMigration.run(in: context)

        #expect(task.category?.name == "Misc")
    }

    @Test @MainActor
    func runningTwiceDoesNotDuplicateSeeds() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        CategoryMigration.run(in: context)
        CategoryMigration.run(in: context)

        let count = try context.fetchCount(FetchDescriptor<TimeTracker2.Category>())
        #expect(count == 4)
    }

    @Test @MainActor
    func runningTwiceDoesNotRelinkAlreadyLinkedTask() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TrackedTask(name: "Already linked", legacyCategoryRawValue: "App")
        context.insert(task)
        try context.save()

        CategoryMigration.run(in: context)
        let firstLink = task.category
        #expect(firstLink?.name == "App")

        CategoryMigration.run(in: context)
        #expect(task.category?.persistentModelID == firstLink?.persistentModelID)
    }

    @Test @MainActor
    func unmatchedRawValueStaysNilWhenNoMiscExists() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Pre-populate user-defined categories with no "Misc". This mimics the
        // real-world scenario where the seed step never persisted on first
        // launch and the user created their own categories before opening Tasks.
        let work = TimeTracker2.Category(name: "Work", colorName: "blue",
                                         iconSymbol: "app.fill", order: 0)
        let personal = TimeTracker2.Category(name: "Personal", colorName: "green",
                                             iconSymbol: "globe", order: 1)
        context.insert(work)
        context.insert(personal)

        let orphan = TrackedTask(name: "Legacy", legacyCategoryRawValue: "App")
        context.insert(orphan)
        try context.save()

        CategoryMigration.run(in: context)

        #expect(orphan.category == nil)
        // Sanity: existing user categories must not have been clobbered.
        let names = try context.fetch(FetchDescriptor<TimeTracker2.Category>()).map(\.name).sorted()
        #expect(names == ["Personal", "Work"])
    }

    @Test @MainActor
    func unmatchedRawValueStaysNilWhenMiscIsArchived() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Seed the four defaults, then archive Misc — the back-link must
        // refuse to assign orphans to an archived row even as a fallback.
        CategoryMigration.run(in: context)
        let misc = try context.fetch(FetchDescriptor<TimeTracker2.Category>())
            .first { $0.name == "Misc" }
        #expect(misc != nil)
        misc?.isArchived = true
        try context.save()

        let orphan = TrackedTask(name: "Legacy", legacyCategoryRawValue: "Bogus")
        context.insert(orphan)
        try context.save()

        CategoryMigration.run(in: context)

        #expect(orphan.category == nil)
    }
}
