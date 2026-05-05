//
//  CategoryReorderTests.swift
//  TimeTracker2Tests
//

import Testing
import SwiftData
import Foundation
@testable import TimeTracker2

struct CategoryReorderTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TimeTracker2.Category.self, TrackedTask.self, TimeEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test @MainActor
    func movingMiddleItemNormalisesOrder() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let names = ["A", "B", "C", "D"]
        let cats: [TimeTracker2.Category] = names.enumerated().map { (idx, name) in
            let c = TimeTracker2.Category(name: name, colorName: "blue",
                                          iconSymbol: "app.fill", order: idx)
            context.insert(c)
            return c
        }
        try context.save()

        // Move "C" (index 2) to position 0.
        var working = cats
        let moved = working.remove(at: 2)
        working.insert(moved, at: 0)
        CategoryOrdering.normaliseOrder(of: working)

        let descriptor = FetchDescriptor<TimeTracker2.Category>(sortBy: [SortDescriptor(\TimeTracker2.Category.order)])
        let stored = try context.fetch(descriptor)
        #expect(stored.map(\.name) == ["C", "A", "B", "D"])
        #expect(stored.map(\.order) == [0, 1, 2, 3])
    }
}
