//
//  CategoryMigration.swift
//  TimeTracker2
//

import Foundation
import SwiftData

enum CategoryMigration {
    /// Seeds the four legacy categories on a store with no Category rows and
    /// back-links every task that lacks a `category` relationship. Safe to run
    /// on every launch: seed insertion is gated on the empty-table check, and
    /// back-linking only touches tasks whose category is nil. Tasks whose
    /// legacy raw value doesn't match any active category — and where no
    /// active "Misc" category exists as a fallback — are intentionally left
    /// nil so the user can resolve them via the Uncategorized bucket rather
    /// than being auto-assigned to an arbitrary custom category.
    @MainActor
    static func run(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let seeds = existing.isEmpty ? insertSeeds(in: context) : existing

        backLinkTasks(seeds: seeds, in: context)

        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }

    @discardableResult
    private static func insertSeeds(in context: ModelContext) -> [Category] {
        let definitions: [(name: String, color: String, icon: String)] = [
            ("App", "blue", "app.fill"),
            ("Portal", "purple", "globe"),
            ("Back Office", "orange", "building.2.fill"),
            ("Misc", "gray", "ellipsis.circle.fill"),
        ]
        var seeds: [Category] = []
        for (index, def) in definitions.enumerated() {
            let category = Category(name: def.name,
                                    colorName: def.color,
                                    iconSymbol: def.icon,
                                    order: index)
            context.insert(category)
            seeds.append(category)
        }
        return seeds
    }

    private static func backLinkTasks(seeds: [Category], in context: ModelContext) {
        // Match against active categories only — assigning a legacy task to an
        // archived row would silently hide it. Use a uniquing initialiser so a
        // duplicate-name pair (allowed when one is archived) doesn't trap.
        let active = seeds.filter { !$0.isArchived }
        let byName = Dictionary(active.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let misc = byName["Misc"]

        let descriptor = FetchDescriptor<TrackedTask>(
            predicate: #Predicate { $0.category == nil }
        )
        let unlinked = (try? context.fetch(descriptor)) ?? []

        for task in unlinked {
            // Leave the task nil if neither an exact-name nor Misc fallback exists.
            // The Tasks tab surfaces nil-category tasks under "Uncategorized" so the
            // user can fix them by hand instead of being auto-assigned to a random
            // custom category.
            if let target = byName[task.categoryRawValue] ?? misc {
                task.category = target
            }
        }
    }
}
