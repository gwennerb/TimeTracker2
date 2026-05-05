//
//  CategoryValidationTests.swift
//  TimeTracker2Tests
//

import Testing
import SwiftUI
import SwiftData
@testable import TimeTracker2

struct CategoryValidationTests {
    @Test func colorPaletteFallsBackToGrayForUnknownKey() async throws {
        let category = Category(name: "Anything", colorName: "doesNotExist",
                                iconSymbol: "app.fill", order: 0)
        #expect(category.color == .gray)
    }

    @Test func colorPaletteResolvesKnownKey() async throws {
        let category = Category(name: "App", colorName: "blue",
                                iconSymbol: "app.fill", order: 0)
        #expect(category.color == .blue)
    }

    @Test func iconPaletteContainsSeedSymbols() async throws {
        for symbol in ["app.fill", "globe", "building.2.fill", "ellipsis.circle.fill"] {
            #expect(Category.iconPalette.contains(symbol),
                    "Seed icon \(symbol) must remain in the curated palette so migration produces stable output")
        }
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Category.self, TrackedTask.self, TimeEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test @MainActor
    func emptyNameIsRejected() async throws {
        let container = try makeContainer()
        let result = CategoryValidation.validate(name: "   ",
                                                 editing: nil,
                                                 in: container.mainContext)
        #expect(result == .empty)
    }

    @Test @MainActor
    func duplicateActiveNameIsRejectedCaseInsensitively() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Category(name: "App", colorName: "blue",
                                iconSymbol: "app.fill", order: 0))
        try context.save()

        let result = CategoryValidation.validate(name: "  app  ",
                                                 editing: nil,
                                                 in: context)
        #expect(result == .duplicate)
    }

    @Test @MainActor
    func duplicateAgainstArchivedIsAllowed() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Category(name: "App", colorName: "blue",
                                iconSymbol: "app.fill", order: 0,
                                isArchived: true))
        try context.save()

        let result = CategoryValidation.validate(name: "App",
                                                 editing: nil,
                                                 in: context)
        #expect(result == .ok)
    }

    @Test @MainActor
    func editingDoesNotConflictWithSelf() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let category = Category(name: "App", colorName: "blue",
                                iconSymbol: "app.fill", order: 0)
        context.insert(category)
        try context.save()

        let result = CategoryValidation.validate(name: "app",
                                                 editing: category,
                                                 in: context)
        #expect(result == .ok)
    }
}
