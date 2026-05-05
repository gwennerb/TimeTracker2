//
//  CategoryMigration.swift
//  TimeTracker2
//

import Foundation
import SwiftData

enum CategoryMigration {
    nonisolated(unsafe) static let defaultsKey = "categoriesMigratedV1"

    /// Seeds the four legacy categories on first launch and back-links every task
    /// that lacks a `category` relationship. Idempotent: subsequent invocations
    /// short-circuit on the UserDefaults flag, and even if the flag is wiped the
    /// empty-table guard prevents duplicate seeds.
    ///
    /// `defaultsKey == nil` skips the UserDefaults gate (used by tests).
    @MainActor
    static func run(in context: ModelContext, defaultsKey: String? = CategoryMigration.defaultsKey) {
        if let key = defaultsKey, UserDefaults.standard.bool(forKey: key) {
            return
        }

        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let seeds = existing.isEmpty ? insertSeeds(in: context) : existing

        backLinkTasks(seeds: seeds, in: context)

        do {
            try context.save()
        } catch {
            // Discard inserted seeds and pending back-link mutations so the
            // context matches the on-disk state. The UserDefaults flag stays
            // unset, so the next launch retries from a clean slate.
            context.rollback()
            return
        }

        if let key = defaultsKey {
            UserDefaults.standard.set(true, forKey: key)
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
        let byName = Dictionary(uniqueKeysWithValues: seeds.map { ($0.name, $0) })
        let misc = byName["Misc"] ?? seeds.first

        let descriptor = FetchDescriptor<TrackedTask>(
            predicate: #Predicate { $0.category == nil }
        )
        let unlinked = (try? context.fetch(descriptor)) ?? []

        for task in unlinked {
            let target = byName[task.categoryRawValue] ?? misc
            task.category = target
        }
    }
}
