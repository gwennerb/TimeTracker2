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

        CategoryMigration.run(in: context, defaultsKey: nil)

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

        CategoryMigration.run(in: context, defaultsKey: nil)

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

        CategoryMigration.run(in: context, defaultsKey: nil)

        #expect(task.category?.name == "Misc")
    }

    @Test @MainActor
    func runningTwiceDoesNotDuplicateSeeds() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        CategoryMigration.run(in: context, defaultsKey: nil)
        CategoryMigration.run(in: context, defaultsKey: nil)

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

        CategoryMigration.run(in: context, defaultsKey: nil)
        let firstLink = task.category
        #expect(firstLink?.name == "App")

        CategoryMigration.run(in: context, defaultsKey: nil)
        #expect(task.category?.persistentModelID == firstLink?.persistentModelID)
    }
}
