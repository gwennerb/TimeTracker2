# User-Configurable Categories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded `TaskCategory` enum with a user-managed `Category` SwiftData model. Users can add, edit (name / color / icon), reorder, and archive categories from a new Settings tab while every existing task and historical entry stays intact.

**Architecture:** Introduce a new `@Model Category` with a curated color palette and SF Symbol palette. Add a `category: Category?` relationship on `TrackedTask`, run a one-time runtime migration to seed the four legacy categories and back-link existing tasks, then progressively migrate every view/viewmodel that previously read `TaskCategory`. Build a Settings tab (refactored from the existing reminders settings) that hosts a Categories section with reorder, archive, and an add/edit sheet. The deprecated `categoryRawValue` is preserved as a one-release safety net per the spec.

**Tech Stack:** Swift 5, SwiftUI, SwiftData (lightweight migration), Foundation. macOS target 26.1, Xcode 26.1.1. The Xcode project uses `PBXFileSystemSynchronizedRootGroup`, so adding files under `TimeTracker2/` automatically includes them in the build — no `.pbxproj` edits required.

**Spec:** [docs/superpowers/specs/2026-05-05-user-configurable-categories-design.md](../specs/2026-05-05-user-configurable-categories-design.md)

---

## File map

**Created:**
- `TimeTracker2/Models/Category.swift` — new `@Model` plus `colorPalette` + `iconPalette` static dictionaries.
- `TimeTracker2/Services/CategoryValidation.swift` — name-trim + uniqueness checks.
- `TimeTracker2/Services/CategoryMigration.swift` — idempotent runtime seed + back-link.
- `TimeTracker2/Views/Settings/SettingsView.swift` — new tab host (ScrollView of section cards).
- `TimeTracker2/Views/Settings/RemindersSection.swift` — body lifted from old `ReminderSettingsView`.
- `TimeTracker2/Views/Settings/CategoriesSection.swift` — list/reorder/archive/add UI.
- `TimeTracker2/Views/Settings/CategoryEditSheet.swift` — single sheet for add+edit.
- `TimeTracker2Tests/CategoryMigrationTests.swift` — fresh install, mixed enum values, missing-value fallback, idempotency.
- `TimeTracker2Tests/CategoryValidationTests.swift` — trim + case-insensitive uniqueness on active categories.
- `TimeTracker2Tests/CategoryReorderTests.swift` — manual reorder normalises `order` to `0..<n`.

**Modified:**
- `TimeTracker2/Models/TrackedTask.swift` — adds `category: Category?` relationship, drops the computed `category: TaskCategory` accessor, keeps `categoryRawValue` as a deprecated stored property, init takes an optional `Category`.
- `TimeTracker2/TimeTracker2App.swift` — schema includes `Category.self`, runs `CategoryMigration` after `ProjectMigration` on launch, switches `Settings { … }` window to `SettingsView()`.
- `TimeTracker2/ContentView.swift` — `.settings` case routes to `SettingsView()`.
- `TimeTracker2/ViewModels/CalendarViewModel.swift` — `categoriesForDate` returns `Set<Category>`.
- `TimeTracker2/ViewModels/SummaryViewModel.swift` — works on `Category` instead of `TaskCategory`. Callers pass an active-category `[Category]` parameter so the viewmodel stays free of `@Query`.
- `TimeTracker2/Views/Calendar/CalendarView.swift` — `DayCell` accepts `Set<Category>`.
- `TimeTracker2/Views/Calendar/TimeEntrySheet.swift` — both pickers (`Add New Entry` filter, `NewTaskSheet`) query active `Category`. Existing entry rows render via `task.category?.iconSymbol`.
- `TimeTracker2/Views/QuickEntry/QuickEntryView.swift` — reads `task.category?.iconSymbol` / `task.category?.color`.
- `TimeTracker2/Views/Tasks/TasksView.swift` — groups tasks by `task.category` over the active-categories query, adds local `showArchived` toggle, `EditTaskSheet` picker queries active categories.
- `TimeTracker2/Views/Summary/SummaryView.swift` — iterates active-category query for `categoryCards`, adds local `showArchived` toggle, `expandedCategories` keyed by `PersistentIdentifier`.
- `TimeTracker2Tests/TimeTracker2Tests.swift` — updates `TrackedTask` constructions to use the new `Category` initializer.

**Deleted:**
- `TimeTracker2/Models/TaskCategory.swift` (final cleanup task only).

---

## Build / test commands

Use these commands literally:

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test
```

`-quiet` suppresses progress noise and keeps the output focused on warnings/errors. Both commands respect Xcode's incremental build cache.

When a step says "Run build" without further qualification, run the first command. When it says "Run tests", run the second.

---

### Task 1: Add `Category` model with curated palettes

**Files:**
- Create: `TimeTracker2/Models/Category.swift`
- Test: `TimeTracker2Tests/CategoryValidationTests.swift` (palette-only assertions added in the next task — for now we exercise the model via a lightweight smoke test)

We start with the data type because everything downstream depends on it. A quick smoke test confirms the palettes load and the lookup helper falls back on unknown keys.

- [ ] **Step 1.1: Add a smoke test for the colour palette fallback**

Create `TimeTracker2Tests/CategoryValidationTests.swift`:

```swift
//
//  CategoryValidationTests.swift
//  TimeTracker2Tests
//

import Testing
import SwiftUI
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
}
```

- [ ] **Step 1.2: Run tests; expect a compile error**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test
```

Expected: build fails with "cannot find type 'Category' in scope".

- [ ] **Step 1.3: Implement `Category.swift`**

Create `TimeTracker2/Models/Category.swift`:

```swift
//
//  Category.swift
//  TimeTracker2
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Category {
    var name: String
    var colorName: String
    var iconSymbol: String
    var order: Int
    var isArchived: Bool
    var creationDate: Date

    @Relationship(deleteRule: .nullify, inverse: \TrackedTask.category)
    var tasks: [TrackedTask]

    init(name: String,
         colorName: String,
         iconSymbol: String,
         order: Int,
         isArchived: Bool = false,
         creationDate: Date = Date()) {
        self.name = name
        self.colorName = colorName
        self.iconSymbol = iconSymbol
        self.order = order
        self.isArchived = isArchived
        self.creationDate = creationDate
        self.tasks = []
    }
}

extension Category {
    /// Resolved SwiftUI colour for the stored palette key. Falls back to `.gray`
    /// so an out-of-band value (e.g. seeded by a future build) never crashes.
    var color: Color {
        Category.colorPalette[colorName] ?? .gray
    }

    /// Curated palette. Keys are stored on disk; do not rename keys without a migration.
    static let colorPalette: [String: Color] = [
        "blue": .blue,
        "purple": .purple,
        "orange": .orange,
        "gray": .gray,
        "green": .green,
        "pink": .pink,
        "red": .red,
        "yellow": .yellow,
        "teal": .teal,
        "indigo": .indigo,
    ]

    /// Display order for swatches in the edit sheet.
    static let colorPaletteOrder: [String] = [
        "blue", "purple", "orange", "gray", "green",
        "pink", "red", "yellow", "teal", "indigo",
    ]

    /// Curated SF Symbol set surfaced in the icon picker.
    static let iconPalette: [String] = [
        "app.fill", "globe", "building.2.fill", "ellipsis.circle.fill",
        "doc.text.fill", "hammer.fill", "bubble.left.fill", "calendar",
        "paintbrush.fill", "gearshape.fill", "terminal.fill", "gauge",
        "megaphone.fill", "chart.line.uptrend.xyaxis", "sparkles",
        "lock.fill", "person.2.fill", "lightbulb.fill",
        "square.and.pencil", "tray.full.fill",
    ]
}
```

- [ ] **Step 1.4: Run build to verify the model compiles**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: build error inside `Category` claiming `\TrackedTask.category` is unknown — that's expected, the relationship inverse only resolves once Task 4 lands. **Comment out the `@Relationship` line and the `tasks` property for now** so this task can be committed:

```swift
    // Re-enabled in Task 4 once TrackedTask gains a stored `category` relationship.
    // @Relationship(deleteRule: .nullify, inverse: \TrackedTask.category)
    // var tasks: [TrackedTask] = []
```

Re-run the build:

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: build succeeds.

- [ ] **Step 1.5: Run the new tests**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test -only-testing:TimeTracker2Tests/CategoryValidationTests
```

Expected: all three tests pass.

- [ ] **Step 1.6: Commit**

```bash
git add TimeTracker2/Models/Category.swift TimeTracker2Tests/CategoryValidationTests.swift
git commit -m "Add Category SwiftData model with curated colour and icon palettes"
```

---

### Task 2: Implement `CategoryValidation` and extend the test file

**Files:**
- Create: `TimeTracker2/Services/CategoryValidation.swift`
- Modify: `TimeTracker2Tests/CategoryValidationTests.swift`

The Settings sheet needs to enforce non-empty trimmed names and case-insensitive uniqueness scoped to non-archived categories. We isolate that logic so both add and edit flows reuse it and so it has direct unit coverage.

- [ ] **Step 2.1: Add validation tests**

Append to `TimeTracker2Tests/CategoryValidationTests.swift`:

```swift
import SwiftData

extension CategoryValidationTests {

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
```

- [ ] **Step 2.2: Run tests; expect compile failure on `CategoryValidation`**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test -only-testing:TimeTracker2Tests/CategoryValidationTests
```

Expected: "cannot find 'CategoryValidation' in scope".

- [ ] **Step 2.3: Implement `CategoryValidation.swift`**

Create `TimeTracker2/Services/CategoryValidation.swift`:

```swift
//
//  CategoryValidation.swift
//  TimeTracker2
//

import Foundation
import SwiftData

enum CategoryValidationResult: Equatable {
    case ok
    case empty
    case duplicate
}

enum CategoryValidation {
    /// Validates a proposed category name. `editing` is the category being edited
    /// (nil for add). Uniqueness is case-insensitive and scoped to non-archived
    /// categories — archived rows can hold any name without blocking new active rows.
    static func validate(name: String,
                         editing: Category?,
                         in context: ModelContext) -> CategoryValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let descriptor = FetchDescriptor<Category>()
        guard let all = try? context.fetch(descriptor) else { return .ok }

        let lowered = trimmed.lowercased()
        let conflict = all.first { existing in
            guard !existing.isArchived else { return false }
            if let editing, existing.persistentModelID == editing.persistentModelID {
                return false
            }
            return existing.name.lowercased() == lowered
        }
        return conflict == nil ? .ok : .duplicate
    }

    /// Convenience for callers that just need the trimmed value once validation passes.
    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2.4: Run validation tests**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test -only-testing:TimeTracker2Tests/CategoryValidationTests
```

Expected: all 7 tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add TimeTracker2/Services/CategoryValidation.swift TimeTracker2Tests/CategoryValidationTests.swift
git commit -m "Add CategoryValidation with trim + scoped uniqueness checks"
```

---

### Task 3: Implement `CategoryMigration` (idempotent seed + back-link)

**Files:**
- Create: `TimeTracker2/Services/CategoryMigration.swift`
- Create: `TimeTracker2Tests/CategoryMigrationTests.swift`

The migration runs once per install. On a fresh database it inserts the four seed categories. On an upgrade, it links every existing `TrackedTask` to the seed whose `name` matches the legacy `categoryRawValue`, falling back to "Misc" for unrecognised values. Idempotency relies on the empty-table guard: re-running with seeds already present links only nil-category tasks.

The migration writes via `task.category = seed`. That requires `TrackedTask` to expose the new stored property — which is added in Task 4. To unblock the tests now, **CategoryMigration takes the optional category as a closure-injected setter so the implementation only assumes the property exists at the call site**. Once Task 4 lands, we can replace the closure with direct assignment.

> ⚠️ Implementation note: there is no chicken-and-egg here as long as we accept that the migration *file* exists ahead of the property and is only wired into the app's launch sequence in Task 5. We test it with a stub `TrackedTaskLike` adapter in this task.

- [ ] **Step 3.1: Add migration tests**

Create `TimeTracker2Tests/CategoryMigrationTests.swift`:

```swift
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
        let schema = Schema([Category.self, TrackedTask.self, TimeEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test @MainActor
    func freshInstallSeedsFourCategoriesInOrder() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        CategoryMigration.run(in: context, defaultsKey: nil)

        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.order)])
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

        let count = try context.fetchCount(FetchDescriptor<Category>())
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
```

- [ ] **Step 3.2: Add a test-only convenience initializer to TrackedTask**

In `TimeTracker2/Models/TrackedTask.swift`, append this internal-only convenience that the tests use to populate `categoryRawValue` without going through `TaskCategory`. We will remove it as part of Task 4 once `TrackedTask` has the new shape.

```swift
extension TrackedTask {
    /// Test/migration helper. Lets us construct a task whose enum-based legacy
    /// category value is set explicitly (including bogus values) without going
    /// through the `TaskCategory` enum.
    convenience init(name: String, legacyCategoryRawValue: String,
                     creationDate: Date = Date(), isArchived: Bool = false) {
        self.init(name: name, category: .misc,
                  creationDate: creationDate, isArchived: isArchived)
        self.categoryRawValue = legacyCategoryRawValue
    }
}
```

- [ ] **Step 3.3: Implement `CategoryMigration.swift`**

Create `TimeTracker2/Services/CategoryMigration.swift`:

```swift
//
//  CategoryMigration.swift
//  TimeTracker2
//

import Foundation
import SwiftData

enum CategoryMigration {
    static let defaultsKey = "categoriesMigratedV1"

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
            // If the save fails the UserDefaults flag stays unset, so the next
            // launch retries. We deliberately do not crash.
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
```

- [ ] **Step 3.4: Run migration tests**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test -only-testing:TimeTracker2Tests/CategoryMigrationTests
```

Expected: tests fail to compile because `TrackedTask.category` (the stored relationship) does not yet exist. That is the cue for Task 4. **Do not commit Task 3 yet** — leave the changes staged-but-uncommitted and proceed to Task 4. We will commit Tasks 3+4 together once everything compiles and passes.

```bash
git status
```

Expected: `Models/TrackedTask.swift`, `Services/CategoryMigration.swift`, `TimeTracker2Tests/CategoryMigrationTests.swift` show as modified/new but not committed.

---

### Task 4: Schema swap on `TrackedTask` and re-link the relationship inverse

**Files:**
- Modify: `TimeTracker2/Models/TrackedTask.swift`
- Modify: `TimeTracker2/Models/Category.swift`
- Modify: `TimeTracker2Tests/TimeTracker2Tests.swift`

We replace the computed `category: TaskCategory` accessor with a stored `category: Category?` relationship. `categoryRawValue` stays as a deprecated stored property for one release. Every existing call site that read `task.category` (returning `TaskCategory`) breaks here — we'll repair them in Tasks 5–11.

- [ ] **Step 4.1: Replace `TrackedTask.swift`**

```swift
//
//  TrackedTask.swift
//  TimeTracker2
//

import Foundation
import SwiftData

@Model
final class TrackedTask {
    var name: String

    /// Deprecated: the legacy enum raw value. Kept for one release as a migration
    /// safety net; remove via a versioned schema migration once `category` is
    /// confirmed populated for all installs.
    var categoryRawValue: String

    var creationDate: Date
    var isArchived: Bool

    @Relationship(deleteRule: .nullify)
    var category: Category?

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.task)
    var entries: [TimeEntry]

    init(name: String,
         category: Category? = nil,
         creationDate: Date = Date(),
         isArchived: Bool = false) {
        self.name = name
        self.categoryRawValue = category?.name ?? ""
        self.creationDate = creationDate
        self.isArchived = isArchived
        self.category = category
        self.entries = []
    }

    /// Legacy initializer kept for tests written against the old `TaskCategory`
    /// enum. Uses the enum's raw value to populate `categoryRawValue` so the
    /// migration can still re-link them. Will be retired once tests adopt
    /// the `Category` model directly.
    convenience init(name: String,
                     category: TaskCategory,
                     creationDate: Date = Date(),
                     isArchived: Bool = false) {
        self.init(name: name, category: nil as Category?,
                  creationDate: creationDate, isArchived: isArchived)
        self.categoryRawValue = category.rawValue
    }

    /// Test/migration helper. Lets us construct a task whose legacy raw value is
    /// set explicitly (including bogus values).
    convenience init(name: String,
                     legacyCategoryRawValue: String,
                     creationDate: Date = Date(),
                     isArchived: Bool = false) {
        self.init(name: name, category: nil as Category?,
                  creationDate: creationDate, isArchived: isArchived)
        self.categoryRawValue = legacyCategoryRawValue
    }

    var lastUsedDate: Date? {
        entries.map(\.date).max()
    }
}

extension Array where Element == TrackedTask {
    /// Sort by most-recently-used desc, then entry count desc, then name.
    func sortedByRecency() -> [TrackedTask] {
        sorted { lhs, rhs in
            let l = lhs.lastUsedDate ?? .distantPast
            let r = rhs.lastUsedDate ?? .distantPast
            if l != r { return l > r }
            if lhs.entries.count != rhs.entries.count { return lhs.entries.count > rhs.entries.count }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
```

Note: we keep the `TaskCategory`-based convenience initializer so the existing test file in `TimeTracker2Tests/TimeTracker2Tests.swift` keeps compiling until Task 7 updates it. The test-only convenience added in Task 3.2 is folded into this file.

- [ ] **Step 4.2: Re-enable the inverse relationship on `Category`**

Open `TimeTracker2/Models/Category.swift` and replace the commented relationship block from Task 1.4 with the live version:

```swift
    @Relationship(deleteRule: .nullify, inverse: \TrackedTask.category)
    var tasks: [TrackedTask]
```

Restore the `tasks = []` line in `init`.

- [ ] **Step 4.3: Run build — expect cascading compile errors at every `task.category` read site**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: errors of the form "value of type 'Category?' has no member 'icon'" / "no member 'color'" / "no member 'displayName'" in:
- `ViewModels/CalendarViewModel.swift`
- `ViewModels/SummaryViewModel.swift`
- `Views/Calendar/CalendarView.swift`
- `Views/Calendar/TimeEntrySheet.swift`
- `Views/QuickEntry/QuickEntryView.swift`
- `Views/Tasks/TasksView.swift`
- `Views/Summary/SummaryView.swift`

This is expected. Tasks 5–11 fix them one file at a time. We deliberately do not commit yet.

---

### Task 5: Migrate `CalendarViewModel` and `CalendarView`/`DayCell`

**Files:**
- Modify: `TimeTracker2/ViewModels/CalendarViewModel.swift`
- Modify: `TimeTracker2/Views/Calendar/CalendarView.swift`

`DayCell` only needs the colour — switching its category set type to `Set<Category>` and rendering through `category.color` is enough.

- [ ] **Step 5.1: Update `CalendarViewModel.categoriesForDate`**

Find:
```swift
    func categoriesForDate(_ date: Date, entries: [TimeEntry]) -> Set<TaskCategory> {
        let dayEntries = entriesForDate(date, entries: entries)
        return Set(dayEntries.compactMap { $0.task?.category })
    }
```

Replace with:
```swift
    func categoriesForDate(_ date: Date, entries: [TimeEntry]) -> Set<Category> {
        let dayEntries = entriesForDate(date, entries: entries)
        return Set(dayEntries.compactMap { $0.task?.category })
    }
```

- [ ] **Step 5.2: Update `DayCell` in `CalendarView.swift`**

Find:
```swift
    let categories: Set<TaskCategory>
```
Replace with:
```swift
    let categories: Set<Category>
```

The body of `DayCell` already iterates `categories` via `ForEach(Array(categories).prefix(3), id: \.self)`. Swap `category.color` (still works — the new model exposes `color: Color`). Verify the pre-existing `Circle().fill(category.color)` line compiles unchanged.

- [ ] **Step 5.3: Run build**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: errors persist in other files but not in `CalendarViewModel.swift` or `CalendarView.swift`.

---

### Task 6: Migrate `SummaryViewModel`

**Files:**
- Modify: `TimeTracker2/ViewModels/SummaryViewModel.swift`
- Modify: `TimeTracker2Tests/TimeTracker2Tests.swift`

The viewmodel exposes per-category aggregation methods that are called from `SummaryView`. We change the type from `TaskCategory` to `Category`, and where the existing code looped over `TaskCategory.allCases`, we now require the caller to pass an active-category list. That keeps the viewmodel free of `@Query` and lets the view stay the source of category ordering.

The Discord/text exporter loops over `TaskCategory.allCases` to build per-project category subtotals. We change that loop to take an injected `[Category]` parameter.

- [ ] **Step 6.1: Replace per-category APIs**

Find the existing block in `SummaryViewModel.swift`:

```swift
    func entriesByCategory(_ entries: [TimeEntry]) -> [TaskCategory: [TimeEntry]] {
        let scopedEntries = scopedEntriesForMonth(entries)
        var grouped: [TaskCategory: [TimeEntry]] = [:]

        for category in TaskCategory.allCases {
            let categoryEntries = scopedEntries.filter { $0.task?.category == category }
            if !categoryEntries.isEmpty {
                grouped[category] = categoryEntries
            }
        }

        return grouped
    }

    func totalHoursForCategory(_ category: TaskCategory, entries: [TimeEntry]) -> Double {
        entriesByCategory(entries)[category]?.reduce(0) { $0 + $1.duration } ?? 0
    }

    func taskHoursForCategory(_ category: TaskCategory, entries: [TimeEntry]) -> [(task: TrackedTask, hours: Double)] {
        guard let categoryEntries = entriesByCategory(entries)[category] else { return [] }
        // … unchanged body …
    }
```

Replace with:

```swift
    /// Group entries by their task's category. Entries whose task has no category
    /// (shouldn't happen post-migration) are dropped — historic data without
    /// a category is shown in a separate "Uncategorized" bucket.
    func entriesByCategory(_ entries: [TimeEntry]) -> [PersistentIdentifier: [TimeEntry]] {
        let scopedEntries = scopedEntriesForMonth(entries)
        var grouped: [PersistentIdentifier: [TimeEntry]] = [:]
        for entry in scopedEntries {
            guard let categoryID = entry.task?.category?.persistentModelID else { continue }
            grouped[categoryID, default: []].append(entry)
        }
        return grouped
    }

    func totalHoursForCategory(_ category: Category, entries: [TimeEntry]) -> Double {
        entriesByCategory(entries)[category.persistentModelID]?.reduce(0) { $0 + $1.duration } ?? 0
    }

    func taskHoursForCategory(_ category: Category, entries: [TimeEntry]) -> [(task: TrackedTask, hours: Double)] {
        guard let categoryEntries = entriesByCategory(entries)[category.persistentModelID] else { return [] }

        var taskHours: [String: (task: TrackedTask, hours: Double)] = [:]
        for entry in categoryEntries {
            guard let task = entry.task else { continue }
            let key = task.name
            if let existing = taskHours[key] {
                taskHours[key] = (task: existing.task, hours: existing.hours + entry.duration)
            } else {
                taskHours[key] = (task: task, hours: entry.duration)
            }
        }
        return taskHours.values.sorted { $0.hours > $1.hours }
    }
```

- [ ] **Step 6.2: Inject categories into the text exporter**

Find:
```swift
    func exportText(for entries: [TimeEntry]) -> String {
        if let project = selectedProject {
            return exportTextForProject(project, entries: entries)
        }
        return exportTextForAllProjects(entries: entries)
    }
```
Replace with:
```swift
    func exportText(for entries: [TimeEntry], categories: [Category]) -> String {
        if let project = selectedProject {
            return exportTextForProject(project, entries: entries, categories: categories)
        }
        return exportTextForAllProjects(entries: entries, categories: categories)
    }
```

Find the `private func exportTextForAllProjects(entries:)` and `private func exportTextForProject(_:entries:)` signatures and add `categories: [Category]` to each. Plumb that argument into `projectSection(_:entries:)` (rename to `projectSection(_:entries:categories:)`):

```swift
    private func exportTextForAllProjects(entries: [TimeEntry], categories: [Category]) -> String {
        let monthEntries = entriesForMonth(entries)
        var lines: [String] = []

        lines.append("TimeTracker Summary - \(monthYearString)")
        lines.append("Total Hours: \(formattedHours(monthEntries.reduce(0) { $0 + $1.duration }))h")
        lines.append("")

        if monthEntries.isEmpty {
            lines.append("No entries logged for this month.")
            return lines.joined(separator: "\n")
        }

        let projects = projectsWithEntriesInMonth(entries)
        let unassigned = monthEntries.filter { $0.project == nil }

        lines.append("Project Totals:")
        for project in projects {
            lines.append("- \(project.name): \(formattedHours(totalHoursForProject(project, entries: entries)))h")
        }
        if !unassigned.isEmpty {
            let unassignedHours = unassigned.reduce(0) { $0 + $1.duration }
            lines.append("- (Unassigned): \(formattedHours(unassignedHours))h")
        }
        lines.append("")

        for project in projects {
            lines.append(contentsOf: projectSection(project, entries: entries, categories: categories))
            lines.append("")
        }

        if !unassigned.isEmpty {
            lines.append(contentsOf: unassignedSection(unassigned: unassigned))
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func exportTextForProject(_ project: Project,
                                      entries: [TimeEntry],
                                      categories: [Category]) -> String {
        var lines: [String] = []

        lines.append("TimeTracker Summary - \(monthYearString)")
        lines.append("Project: \(project.name)")
        lines.append("Total Hours: \(formattedHours(totalHoursForProject(project, entries: entries)))h")
        lines.append("")

        let projectEntries = entriesForMonth(entries).filter { $0.project?.id == project.id }
        if projectEntries.isEmpty {
            lines.append("No entries logged for this project this month.")
            return lines.joined(separator: "\n")
        }

        lines.append(contentsOf: projectSection(project, entries: entries,
                                                categories: categories,
                                                includeHeader: false))
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func projectSection(_ project: Project,
                                entries: [TimeEntry],
                                categories: [Category],
                                includeHeader: Bool = true) -> [String] {
        let previousSelection = selectedProject
        selectedProject = project
        defer { selectedProject = previousSelection }

        var lines: [String] = []
        if includeHeader {
            let total = totalHoursForProject(project, entries: entries)
            lines.append("=== \(project.name) — \(formattedHours(total))h ===")
        }

        lines.append("Category Totals:")
        for category in categories {
            let categoryHours = totalHoursForCategory(category, entries: entries)
            guard categoryHours > 0 else { continue }
            lines.append("- \(category.name): \(formattedHours(categoryHours))h")
            for item in taskHoursForCategory(category, entries: entries) {
                lines.append("  - \(item.task.name): \(formattedHours(item.hours))h")
            }
        }

        lines.append("")
        lines.append("Entries:")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let projectEntries = entriesForMonth(entries).filter { $0.project?.id == project.id }
        let sorted = projectEntries.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return (lhs.task?.name ?? "No Task")
                .localizedCaseInsensitiveCompare(rhs.task?.name ?? "No Task") == .orderedAscending
        }
        for entry in sorted {
            lines.append(formatEntryLine(entry, dateFormatter: dateFormatter))
        }
        return lines
    }
```

- [ ] **Step 6.3: Update `formatEntryLine` to read the new model**

Find:
```swift
    private func formatEntryLine(_ entry: TimeEntry, dateFormatter: DateFormatter) -> String {
        let taskName = entry.task?.name ?? "No Task"
        let categoryName = entry.task?.category.displayName ?? "Uncategorized"
        // …
    }
```
Replace `category.displayName` with `category?.name`:
```swift
        let categoryName = entry.task?.category?.name ?? "Uncategorized"
```

- [ ] **Step 6.4: Inject categories into the Discord exporter**

Find:
```swift
    func discordExportText(for entries: [TimeEntry], expectedHours: Double) -> String {
        if let project = selectedProject {
            return discordTextForProject(project, entries: entries)
        }
        return discordTextForAllProjects(entries: entries, expectedHours: expectedHours)
    }
```
Replace with:
```swift
    func discordExportText(for entries: [TimeEntry],
                           expectedHours: Double,
                           categories: [Category]) -> String {
        if let project = selectedProject {
            return discordTextForProject(project, entries: entries, categories: categories)
        }
        return discordTextForAllProjects(entries: entries, expectedHours: expectedHours)
    }
```

Add `categories: [Category]` to `discordTextForProject(_:entries:)` and replace the `for category in TaskCategory.allCases` loop with `for category in categories`. Replace `category.displayName` with `category.name`.

```swift
    private func discordTextForProject(_ project: Project,
                                       entries: [TimeEntry],
                                       categories: [Category]) -> String {
        let projectTotal = totalHoursForProject(project, entries: entries)
        var header: [String] = []
        header.append("**TimeTracker — \(monthYearString) — \(project.name)**")
        header.append("Total: \(formattedHours(projectTotal))h")

        let previousSelection = selectedProject
        selectedProject = project
        defer { selectedProject = previousSelection }

        var rows: [(category: String, task: String, hours: Double)] = []
        for category in categories {
            for item in taskHoursForCategory(category, entries: entries) {
                rows.append((category.name, item.task.name, item.hours))
            }
        }
        // … rest of the method unchanged …
    }
```

`discordTextForAllProjects` does not iterate categories and stays unchanged (besides its outer call signature).

- [ ] **Step 6.5: Update existing summary export tests**

Open `TimeTracker2Tests/TimeTracker2Tests.swift`. Replace the three tests that touch the export to construct categories explicitly and pass them through:

```swift
    @Test func summaryExportIncludesTotalsAndEntries() async throws {
        let viewModel = SummaryViewModel()
        let calendar = Calendar(identifier: .gregorian)
        viewModel.selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!

        let app = Category(name: "App", colorName: "blue", iconSymbol: "app.fill", order: 0)
        let portal = Category(name: "Portal", colorName: "purple", iconSymbol: "globe", order: 1)
        let project = Project(name: "Varberg")
        let appTask = TrackedTask(name: "Feature Work", category: app)
        let portalTask = TrackedTask(name: "Portal Support", category: portal)

        let matchingEntries = [
            TimeEntry(date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))!,
                      duration: 2.0, notes: "Shipped export",
                      task: appTask, project: project),
            TimeEntry(date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!,
                      duration: 1.0, notes: "",
                      task: portalTask, project: project)
        ]
        let nonMatchingEntry = TimeEntry(
            date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            duration: 9.0, notes: "Should be excluded",
            task: appTask, project: project
        )

        let text = viewModel.exportText(for: matchingEntries + [nonMatchingEntry],
                                        categories: [app, portal])

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

        let app = Category(name: "App", colorName: "blue", iconSymbol: "app.fill", order: 0)
        let varberg = Project(name: "Varberg")
        let acme = Project(name: "Acme")
        let task = TrackedTask(name: "Feature Work", category: app)

        let entries = [
            TimeEntry(date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))!,
                      duration: 2.0, notes: "Varberg work",
                      task: task, project: varberg),
            TimeEntry(date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 4))!,
                      duration: 3.0, notes: "Acme work",
                      task: task, project: acme)
        ]

        viewModel.selectedProject = varberg
        let text = viewModel.exportText(for: entries, categories: [app])

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

        let text = viewModel.exportText(for: [], categories: [])

        #expect(text.contains("Total Hours: 0.0h"))
        #expect(text.contains("No entries logged for this month."))
    }
```

- [ ] **Step 6.6: Run the test target**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: build still fails — but only inside view files (TimeEntrySheet, TasksView, etc.). `SummaryViewModel.swift` and the test file should be clean.

---

### Task 7: Migrate `TimeEntrySheet` (incl. `NewTaskSheet`, `TaskRow`, `ExistingEntryRow`)

**Files:**
- Modify: `TimeTracker2/Views/Calendar/TimeEntrySheet.swift`

The sheet has several places to update:

1. The category filter `Picker` at the top of "Add New Entry".
2. The `selectedCategory` `@State` type.
3. The `filteredTasks` computed property's `if let category` block.
4. `ExistingEntryRow` reading `task.category.icon` and `.color`.
5. `TaskRow` (same pattern).
6. `NewTaskSheet` `Picker` and the `category: TaskCategory = .misc` default.

We add a `@Query` for active categories ordered by `order`, and pass it down where needed.

- [ ] **Step 7.1: Update `TimeEntrySheet` body and pickers**

In `TimeEntrySheet`, add at the top with the other `@Query` declarations:

```swift
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]
```

Change:
```swift
    @State private var selectedCategory: TaskCategory?
```
to:
```swift
    @State private var selectedCategory: Category?
```

Update `filteredTasks`:
```swift
    private var filteredTasks: [TrackedTask] {
        var filtered = tasks.filter { !$0.isArchived }

        if let category = selectedCategory {
            filtered = filtered.filter { $0.category?.persistentModelID == category.persistentModelID }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return filtered.sortedByRecency()
    }
```

Update the category Picker block:
```swift
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as Category?)
                        ForEach(activeCategories) { category in
                            Label(category.name, systemImage: category.iconSymbol)
                                .tag(category as Category?)
                        }
                    }
```

- [ ] **Step 7.2: Update `ExistingEntryRow` to read the optional**

Replace the `if let task = entry.task { … }` body in `ExistingEntryRow`:

```swift
                if let task = entry.task {
                    Image(systemName: task.category?.iconSymbol ?? "questionmark.circle")
                        .foregroundStyle(task.category?.color ?? .gray)

                    VStack(alignment: .leading, spacing: 2) {
                        // … unchanged …
                    }
                } else {
                    Text("Unknown Task")
                        .foregroundStyle(.secondary)
                }
```

- [ ] **Step 7.3: Update `TaskRow`**

```swift
struct TaskRow: View {
    let task: TrackedTask
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: task.category?.iconSymbol ?? "questionmark.circle")
                    .foregroundStyle(task.category?.color ?? .gray)

                Text(task.name)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 7.4: Rebuild `NewTaskSheet` to pick from `Category`**

```swift
struct NewTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]

    let onTaskCreated: (TrackedTask) -> Void

    @State private var name: String = ""
    @State private var selectedCategory: Category?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task Name", text: $name)

                    Picker("Category", selection: $selectedCategory) {
                        Text("Select a category…").tag(nil as Category?)
                        ForEach(activeCategories) { category in
                            Label(category.name, systemImage: category.iconSymbol)
                                .tag(category as Category?)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createTask() }
                        .disabled(name.isEmpty || selectedCategory == nil)
                }
            }
            .onAppear { selectedCategory = activeCategories.first }
        }
        .frame(minWidth: 300, minHeight: 200)
    }

    private func createTask() {
        guard let category = selectedCategory else { return }
        let task = TrackedTask(name: name, category: category)
        modelContext.insert(task)
        onTaskCreated(task)
        dismiss()
    }
}
```

- [ ] **Step 7.5: Update `EditEntrySheet` (already in this file)**

`EditEntrySheet` does not directly read `task.category`. It uses `TaskRow`, which we already migrated. No change needed.

- [ ] **Step 7.6: Run build**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: errors only in `QuickEntryView`, `TasksView`, `SummaryView`.

---

### Task 8: Migrate `QuickEntryView`

**Files:**
- Modify: `TimeTracker2/Views/QuickEntry/QuickEntryView.swift`

`QuickEntryRow` is the only thing that reads `task.category`.

- [ ] **Step 8.1: Update `QuickEntryRow.body` icon expression**

Find:
```swift
                Image(systemName: task.category.icon)
                    .foregroundStyle(task.category.color)
```
Replace with:
```swift
                Image(systemName: task.category?.iconSymbol ?? "questionmark.circle")
                    .foregroundStyle(task.category?.color ?? .gray)
```

- [ ] **Step 8.2: Run build**

Expected: errors only in `TasksView` and `SummaryView`.

---

### Task 9: Migrate `TasksView` and `EditTaskSheet`

**Files:**
- Modify: `TimeTracker2/Views/Tasks/TasksView.swift`

We replace the `[(TaskCategory, [TrackedTask])]` grouping with a query over active categories ordered by `order`. We also add the local `showArchived` toggle described in the spec — when on, archived categories' sections appear dimmed with an "Archived" badge. The toggle is `@State`, not persisted.

- [ ] **Step 9.1: Replace `TasksView.body` grouping logic**

```swift
struct TasksView: View {
    @Query(sort: \TrackedTask.name) private var allTasks: [TrackedTask]
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]
    @Query(filter: #Predicate<Category> { $0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var archivedCategories: [Category]

    @State private var showArchivedTasks: Bool = false
    @State private var showArchivedCategories: Bool = false
    @State private var editingTask: TrackedTask?

    private var activeTasks: [TrackedTask] {
        allTasks.filter { !$0.isArchived }
    }

    private var archivedTasks: [TrackedTask] {
        allTasks.filter { $0.isArchived }
    }

    private func tasks(for category: Category, includeArchivedTasks: Bool) -> [TrackedTask] {
        let pool = includeArchivedTasks ? allTasks : activeTasks
        return pool
            .filter { $0.category?.persistentModelID == category.persistentModelID }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                viewHeader

                ForEach(activeCategories) { category in
                    let categoryTasks = tasks(for: category, includeArchivedTasks: false)
                    if !categoryTasks.isEmpty {
                        categorySection(category: category,
                                        tasks: categoryTasks,
                                        archivedCategory: false)
                    }
                }

                if activeTasks.isEmpty && !showArchivedTasks {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "tray")
                    } description: {
                        Text("Tasks created when logging time will appear here.")
                    }
                }

                if showArchivedCategories {
                    ForEach(archivedCategories) { category in
                        let categoryTasks = tasks(for: category, includeArchivedTasks: true)
                        if !categoryTasks.isEmpty {
                            categorySection(category: category,
                                            tasks: categoryTasks,
                                            archivedCategory: true)
                        }
                    }
                }

                if !archivedTasks.isEmpty {
                    archivedTasksSection
                }
            }
            .padding()
        }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task)
        }
    }

    private var viewHeader: some View {
        HStack {
            Text("Tasks")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Toggle("Show archived categories", isOn: $showArchivedCategories)
                .toggleStyle(.switch)
                .help("Reveals categories that have been archived so historical tasks stay reachable.")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func categorySection(category: Category,
                                 tasks: [TrackedTask],
                                 archivedCategory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(category.name, systemImage: category.iconSymbol)
                    .font(.headline)
                    .foregroundStyle(category.color)
                if archivedCategory {
                    Text("Archived")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    taskRow(task: task, archivedCategory: archivedCategory)

                    if task.id != tasks.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .opacity(archivedCategory ? 0.55 : 1.0)
    }

    private func taskRow(task: TrackedTask, archivedCategory: Bool) -> some View {
        Button {
            editingTask = task
        } label: {
            HStack {
                Image(systemName: task.category?.iconSymbol ?? "questionmark.circle")
                    .foregroundStyle(task.category?.color ?? .gray)
                    .frame(width: 24)

                Text(task.name)
                    .lineLimit(1)

                if task.isArchived {
                    Text("Archived task")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(task.entries.count) \(task.entries.count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if task.isArchived {
                Button {
                    task.isArchived = false
                } label: {
                    Label("Unarchive task", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    task.isArchived = true
                } label: {
                    Label("Archive task", systemImage: "archivebox")
                }
            }
        }
    }

    private var archivedTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showArchivedTasks.toggle() }
            } label: {
                HStack {
                    Label("Archived tasks", systemImage: "archivebox")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showArchivedTasks ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if showArchivedTasks {
                VStack(spacing: 0) {
                    ForEach(archivedTasks) { task in
                        taskRow(task: task, archivedCategory: false)

                        if task.id != archivedTasks.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
```

- [ ] **Step 9.2: Replace `EditTaskSheet`**

```swift
struct EditTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]

    let task: TrackedTask

    @State private var name: String
    @State private var selectedCategory: Category?
    @State private var isArchived: Bool

    init(task: TrackedTask) {
        self.task = task
        _name = State(initialValue: task.name)
        _selectedCategory = State(initialValue: task.category)
        _isArchived = State(initialValue: task.isArchived)
    }

    private var pickerCategories: [Category] {
        // Always include the currently selected category, even if it has been archived,
        // so the picker doesn't silently drop the assignment.
        var list = activeCategories
        if let current = selectedCategory,
           !list.contains(where: { $0.persistentModelID == current.persistentModelID }) {
            list.insert(current, at: 0)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task Name", text: $name)

                    Picker("Category", selection: $selectedCategory) {
                        Text("Select a category…").tag(nil as Category?)
                        ForEach(pickerCategories) { category in
                            Label(category.name, systemImage: category.iconSymbol)
                                .tag(category as Category?)
                        }
                    }
                }

                Section {
                    Toggle("Archived", isOn: $isArchived)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        task.name = name
                        task.category = selectedCategory
                        task.isArchived = isArchived
                        dismiss()
                    }
                    .disabled(name.isEmpty || selectedCategory == nil)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 250)
    }
}
```

- [ ] **Step 9.3: Run build**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: errors only in `SummaryView.swift`.

---

### Task 10: Migrate `SummaryView` (incl. `CategoryCard`) and add the archived toggle

**Files:**
- Modify: `TimeTracker2/Views/Summary/SummaryView.swift`

We replace the `TaskCategory.allCases` iteration with the active-categories query, change `expandedCategories` to a `Set<PersistentIdentifier>`, and add a `showArchived` toggle that surfaces archived-category cards (dimmed, with an "Archived" badge).

- [ ] **Step 10.1: Replace state and queries at the top of `SummaryView`**

```swift
struct SummaryView: View {
    @Query private var entries: [TimeEntry]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query private var daysOff: [DayOff]
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]
    @Query(filter: #Predicate<Category> { $0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var archivedCategories: [Category]

    @State private var viewModel = SummaryViewModel()
    @State private var expandedCategories: Set<PersistentIdentifier> = []
    @State private var hasSeededExpansion: Bool = false
    @State private var showArchivedCategories: Bool = false
    @State private var exportStatusMessage: String?
    @State private var isExporting = false
    @State private var exportDocument = SummaryTextDocument(text: "")
```

The default expansion (previously every category open) is replaced by lazy population. We expand any active category ID the first time it shows hours. Update the helper:

```swift
    private func toggleCategory(_ id: PersistentIdentifier) {
        withAnimation {
            if expandedCategories.contains(id) {
                expandedCategories.remove(id)
            } else {
                expandedCategories.insert(id)
            }
        }
    }
```

- [ ] **Step 10.2: Replace `categoryCards`**

```swift
    private var categoryCards: some View {
        VStack(spacing: 12) {
            ForEach(activeCategories) { category in
                let categoryHours = viewModel.totalHoursForCategory(category, entries: entries)
                if categoryHours > 0 {
                    CategoryCard(
                        category: category,
                        totalHours: categoryHours,
                        taskHours: viewModel.taskHoursForCategory(category, entries: entries),
                        isExpanded: expandedCategories.contains(category.persistentModelID),
                        archived: false
                    ) {
                        toggleCategory(category.persistentModelID)
                    }
                }
            }

            if showArchivedCategories {
                ForEach(archivedCategories) { category in
                    let categoryHours = viewModel.totalHoursForCategory(category, entries: entries)
                    if categoryHours > 0 {
                        CategoryCard(
                            category: category,
                            totalHours: categoryHours,
                            taskHours: viewModel.taskHoursForCategory(category, entries: entries),
                            isExpanded: expandedCategories.contains(category.persistentModelID),
                            archived: true
                        ) {
                            toggleCategory(category.persistentModelID)
                        }
                    }
                }
            }
        }
    }
```

- [ ] **Step 10.3: Add the inline archived-categories toggle and seed default expansion**

The original behaviour was "all four categories expanded on first appearance". Preserve that by seeding `expandedCategories` once `activeCategories` first arrives. Append the toggle alongside the existing Copy/Export buttons in `monthHeader`.

Find:
```swift
            Button(action: copyForDiscord) {
                Label("Copy for Discord", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.plain)

            Button(action: exportSummary) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
```

Add the toggle just before `Button(action: copyForDiscord)`:
```swift
            Toggle("Archived", isOn: $showArchivedCategories)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Surface archived categories so historical hours stay reachable.")
```

Then attach a seed to the outer view:
```swift
        .onChange(of: activeCategories) { _, newValue in
            seedExpansionIfNeeded(active: newValue)
        }
        .task { seedExpansionIfNeeded(active: activeCategories) }
```

Add the helper:
```swift
    private func seedExpansionIfNeeded(active: [Category]) {
        guard !hasSeededExpansion, !active.isEmpty else { return }
        expandedCategories = Set(active.map { $0.persistentModelID })
        hasSeededExpansion = true
    }
```

- [ ] **Step 10.4: Update export call sites**

Find:
```swift
    private func exportSummary() {
        exportDocument = SummaryTextDocument(text: viewModel.exportText(for: entries))
        isExporting = true
    }

    private func copyForDiscord() {
        let text = viewModel.discordExportText(
            for: entries,
            expectedHours: viewModel.expectedHoursForMonth(daysOff)
        )
```
Replace with:
```swift
    private var allCategoriesForExport: [Category] {
        activeCategories + archivedCategories
    }

    private func exportSummary() {
        exportDocument = SummaryTextDocument(
            text: viewModel.exportText(for: entries, categories: allCategoriesForExport)
        )
        isExporting = true
    }

    private func copyForDiscord() {
        let text = viewModel.discordExportText(
            for: entries,
            expectedHours: viewModel.expectedHoursForMonth(daysOff),
            categories: allCategoriesForExport
        )
```

- [ ] **Step 10.5: Replace `CategoryCard` to take `Category` and an archived flag**

```swift
struct CategoryCard: View {
    let category: Category
    let totalHours: Double
    let taskHours: [(task: TrackedTask, hours: Double)]
    let isExpanded: Bool
    let archived: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: category.iconSymbol)
                        .font(.title2)
                        .foregroundStyle(category.color)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.headline)
                        if archived {
                            Text("Archived")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(String(format: "%.1fh", totalHours))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !taskHours.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(taskHours, id: \.task.id) { item in
                        TaskHoursRow(taskName: item.task.name,
                                     hours: item.hours,
                                     color: category.color)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(archived ? 0.55 : 1.0)
    }
}
```

- [ ] **Step 10.6: Run build and tests**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test
```

Expected: build succeeds. Test target still fails because `CategoryMigration` is referenced from tests but not yet wired into the app — and because `TimeTracker2App` may need updates. We patch that in Task 11.

---

### Task 11: Wire `CategoryMigration` into the app launch + add `Category` to the schema

**Files:**
- Modify: `TimeTracker2/TimeTracker2App.swift`

- [ ] **Step 11.1: Update `TimeTracker2App.swift`**

```swift
//
//  TimeTracker2App.swift
//  TimeTracker2
//

import SwiftUI
import SwiftData

@main
struct TimeTracker2App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TrackedTask.self,
            TimeEntry.self,
            DayOff.self,
            Project.self,
            Category.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    ProjectMigration.ensureSeed(sharedModelContainer.mainContext)
                    CategoryMigration.run(in: sharedModelContainer.mainContext)
                    await ReminderScheduler.syncFromPreferences()
                }
        }
        .modelContainer(sharedModelContainer)

        Settings {
            // Replaced with SettingsView() in Task 14.
            ReminderSettingsView()
        }
    }
}
```

- [ ] **Step 11.2: Run the full test suite**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test
```

Expected: all tests pass — including the new `CategoryMigrationTests`, `CategoryValidationTests`, and the updated `TimeTracker2Tests` export tests.

- [ ] **Step 11.3: Commit Tasks 1–11 as one coherent migration commit**

The schema swap must land atomically because intermediate states do not compile. Stage everything modified since the last commit:

```bash
git add TimeTracker2/Models/Category.swift \
        TimeTracker2/Models/TrackedTask.swift \
        TimeTracker2/Services/CategoryValidation.swift \
        TimeTracker2/Services/CategoryMigration.swift \
        TimeTracker2/ViewModels/CalendarViewModel.swift \
        TimeTracker2/ViewModels/SummaryViewModel.swift \
        TimeTracker2/Views/Calendar/CalendarView.swift \
        TimeTracker2/Views/Calendar/TimeEntrySheet.swift \
        TimeTracker2/Views/QuickEntry/QuickEntryView.swift \
        TimeTracker2/Views/Tasks/TasksView.swift \
        TimeTracker2/Views/Summary/SummaryView.swift \
        TimeTracker2/TimeTracker2App.swift \
        TimeTracker2Tests/CategoryMigrationTests.swift \
        TimeTracker2Tests/CategoryValidationTests.swift \
        TimeTracker2Tests/TimeTracker2Tests.swift
git commit -m "Replace TaskCategory enum with user-managed Category model and migrate views"
```

---

### Task 12: Add `SettingsView` host and lift the reminders body

**Files:**
- Create: `TimeTracker2/Views/Settings/SettingsView.swift`
- Create: `TimeTracker2/Views/Settings/RemindersSection.swift`

`ReminderSettingsView` becomes a subview that renders inside the new Settings tab. We keep its file alive only because `TimeTracker2App.swift`'s `Settings { }` window references it; we'll switch that to `SettingsView()` too in this task.

- [ ] **Step 12.1: Lift the reminder body into `RemindersSection.swift`**

Create `TimeTracker2/Views/Settings/RemindersSection.swift`:

```swift
//
//  RemindersSection.swift
//  TimeTracker2
//

import SwiftUI
import UserNotifications
import AppKit

struct RemindersSection: View {
    @AppStorage(ReminderPreferences.enabledKey) private var isReminderEnabled = ReminderPreferences.defaultEnabled
    @AppStorage(ReminderPreferences.hourKey) private var reminderHour = ReminderPreferences.defaultHour
    @AppStorage(ReminderPreferences.minuteKey) private var reminderMinute = ReminderPreferences.defaultMinute

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Time Entry Reminder")
                .font(.headline)

            Toggle("Enable weekday reminders", isOn: $isReminderEnabled)

            DatePicker("Reminder time",
                       selection: reminderTimeBinding,
                       displayedComponents: [.hourAndMinute])
                .disabled(!isReminderEnabled)

            Text("Reminders are scheduled Monday to Friday.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("Notification Access")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(authorizationDescription)
                .foregroundStyle(.secondary)
                .font(.caption)
            if authorizationStatus == .denied {
                Button("Open Notification Settings") {
                    openNotificationSettings()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .task { await syncAndRefreshStatus() }
        .onChange(of: isReminderEnabled) { _, _ in
            Task { await syncAndRefreshStatus() }
        }
        .onChange(of: reminderHour) { _, _ in
            Task { await syncAndRefreshStatus() }
        }
        .onChange(of: reminderMinute) { _, _ in
            Task { await syncAndRefreshStatus() }
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let components = DateComponents(hour: reminderHour, minute: reminderMinute)
                if let date = calendar.date(from: components) { return date }
                return calendar.date(from: DateComponents(
                    hour: ReminderPreferences.defaultHour,
                    minute: ReminderPreferences.defaultMinute
                )) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = components.hour ?? ReminderPreferences.defaultHour
                reminderMinute = components.minute ?? ReminderPreferences.defaultMinute
            }
        )
    }

    private var authorizationDescription: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Notifications are allowed."
        case .denied:
            return "Notifications are disabled for TimeTracker2."
        case .notDetermined:
            return "Notification permission will be requested when reminders are enabled."
        @unknown default:
            return "Notification status is unavailable."
        }
    }

    private func syncAndRefreshStatus() async {
        await ReminderScheduler.syncFromPreferences()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { authorizationStatus = settings.authorizationStatus }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 12.2: Create `SettingsView.swift` shell**

Create `TimeTracker2/Views/Settings/SettingsView.swift`:

```swift
//
//  SettingsView.swift
//  TimeTracker2
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CategoriesSection()
                RemindersSection()
            }
            .padding()
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self, Project.self,
                              DayOff.self, Category.self], inMemory: true)
}
```

`CategoriesSection` doesn't yet exist — it will fail to compile until Task 14. We'll add a stub now so this file builds, and replace the stub in Task 14.

Append a stub at the bottom of `SettingsView.swift`:

```swift
private struct CategoriesSection: View {
    var body: some View {
        Text("Categories — TODO Task 14")
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

> Plan note: we'll **delete this stub** in Task 14 when the real `CategoriesSection.swift` lands. The real one will live in its own file.

- [ ] **Step 12.3: Slim down `ReminderSettingsView.swift`**

Replace the whole file with a thin wrapper that delegates to the new section so the macOS `Settings { }` window keeps working:

```swift
//
//  ReminderSettingsView.swift
//  TimeTracker2
//

import SwiftUI

struct ReminderSettingsView: View {
    var body: some View {
        SettingsView()
            .frame(minWidth: 480, minHeight: 360)
    }
}

#Preview {
    ReminderSettingsView()
}
```

- [ ] **Step 12.4: Run build**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: build succeeds.

- [ ] **Step 12.5: Commit**

```bash
git add TimeTracker2/Views/Settings/SettingsView.swift \
        TimeTracker2/Views/Settings/RemindersSection.swift \
        TimeTracker2/Views/Settings/ReminderSettingsView.swift
git commit -m "Lift reminders into RemindersSection and add SettingsView host"
```

---

### Task 13: Build `CategoryEditSheet` (add + edit)

**Files:**
- Create: `TimeTracker2/Views/Settings/CategoryEditSheet.swift`

A single sheet powers both add and edit modes. The form has a live preview row, a `TextField` for the name, a `LazyVGrid` of colour swatches, and a `LazyVGrid` of icon symbols. Save is disabled until validation passes.

- [ ] **Step 13.1: Implement `CategoryEditSheet.swift`**

```swift
//
//  CategoryEditSheet.swift
//  TimeTracker2
//

import SwiftUI
import SwiftData

struct CategoryEditSheet: View {
    enum Mode {
        case add
        case edit(Category)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String
    @State private var colorName: String
    @State private var iconSymbol: String
    @State private var validationError: CategoryValidationResult = .ok

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _colorName = State(initialValue: "blue")
            _iconSymbol = State(initialValue: "app.fill")
        case .edit(let category):
            _name = State(initialValue: category.name)
            _colorName = State(initialValue: category.colorName)
            _iconSymbol = State(initialValue: category.iconSymbol)
        }
    }

    private var resolvedColor: Color {
        Category.colorPalette[colorName] ?? .gray
    }

    private var editingCategory: Category? {
        if case .edit(let c) = mode { return c }
        return nil
    }

    private var canSave: Bool {
        validationError == .ok
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    HStack(spacing: 12) {
                        Image(systemName: iconSymbol)
                            .font(.title2)
                            .foregroundStyle(resolvedColor)
                            .frame(width: 32)
                        Text(name.isEmpty ? "Category name" : name)
                            .font(.headline)
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Name") {
                    TextField("Category name", text: $name)
                        .onChange(of: name) { _, _ in revalidate() }
                    if validationError == .duplicate {
                        Text("Another active category already uses this name.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if validationError == .empty {
                        Text("Name cannot be empty.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                              spacing: 12) {
                        ForEach(Category.colorPaletteOrder, id: \.self) { key in
                            colorSwatch(key: key)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                              spacing: 8) {
                        ForEach(Category.iconPalette, id: \.self) { symbol in
                            iconSwatch(symbol: symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editingCategory == nil ? "New Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { revalidate() }
        }
        .frame(minWidth: 460, minHeight: 540)
    }

    private func colorSwatch(key: String) -> some View {
        let isSelected = key == colorName
        return Button {
            colorName = key
        } label: {
            Circle()
                .fill(Category.colorPalette[key] ?? .gray)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
        .help(key.capitalized)
    }

    private func iconSwatch(symbol: String) -> some View {
        let isSelected = symbol == iconSymbol
        return Button {
            iconSymbol = symbol
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(isSelected ? 0.8 : 0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func revalidate() {
        validationError = CategoryValidation.validate(name: name,
                                                      editing: editingCategory,
                                                      in: modelContext)
    }

    private func save() {
        let trimmed = CategoryValidation.trimmed(name)
        switch mode {
        case .add:
            let nextOrder = nextOrderValue()
            let category = Category(name: trimmed,
                                    colorName: colorName,
                                    iconSymbol: iconSymbol,
                                    order: nextOrder)
            modelContext.insert(category)
        case .edit(let category):
            category.name = trimmed
            category.colorName = colorName
            category.iconSymbol = iconSymbol
        }
        dismiss()
    }

    private func nextOrderValue() -> Int {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { !$0.isArchived }
        )
        let active = (try? modelContext.fetch(descriptor)) ?? []
        return (active.map(\.order).max() ?? -1) + 1
    }
}

#Preview {
    CategoryEditSheet(mode: .add)
        .modelContainer(for: [Category.self, TrackedTask.self, TimeEntry.self,
                              Project.self, DayOff.self], inMemory: true)
}
```

- [ ] **Step 13.2: Run build**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: success. The sheet has no callers yet — that's fine.

- [ ] **Step 13.3: Commit**

```bash
git add TimeTracker2/Views/Settings/CategoryEditSheet.swift
git commit -m "Add CategoryEditSheet with curated colour and icon pickers"
```

---

### Task 14: Build `CategoriesSection` (list, reorder, archive, add)

**Files:**
- Create: `TimeTracker2/Views/Settings/CategoriesSection.swift`
- Modify: `TimeTracker2/Views/Settings/SettingsView.swift` (drop the stub)
- Create: `TimeTracker2Tests/CategoryReorderTests.swift`

We render the active categories with `List` so `.onMove` is available. After every reorder we normalise `order` to a contiguous `0..<n`. Archived categories live behind a `DisclosureGroup`.

- [ ] **Step 14.1: Add reorder normalisation tests**

Create `TimeTracker2Tests/CategoryReorderTests.swift`:

```swift
//
//  CategoryReorderTests.swift
//  TimeTracker2Tests
//

import Testing
import SwiftData
@testable import TimeTracker2

struct CategoryReorderTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Category.self, TrackedTask.self, TimeEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test @MainActor
    func movingMiddleItemNormalisesOrder() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let names = ["A", "B", "C", "D"]
        let cats: [Category] = names.enumerated().map { (idx, name) in
            let c = Category(name: name, colorName: "blue",
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

        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.order)])
        let stored = try context.fetch(descriptor)
        #expect(stored.map(\.name) == ["C", "A", "B", "D"])
        #expect(stored.map(\.order) == [0, 1, 2, 3])
    }
}
```

- [ ] **Step 14.2: Implement `CategoriesSection.swift`**

Create `TimeTracker2/Views/Settings/CategoriesSection.swift`:

```swift
//
//  CategoriesSection.swift
//  TimeTracker2
//

import SwiftUI
import SwiftData

enum CategoryOrdering {
    /// Normalise the `order` field of the supplied list to a contiguous 0..<n.
    /// Pass the list in the order you want it to appear; we'll write the
    /// indices back to each category's `order`.
    static func normaliseOrder(of categories: [Category]) {
        for (index, category) in categories.enumerated() where category.order != index {
            category.order = index
        }
    }
}

struct CategoriesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]
    @Query(filter: #Predicate<Category> { $0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var archivedCategories: [Category]

    @State private var sheetMode: CategoryEditSheet.Mode?
    @State private var showArchivedDisclosure: Bool = false
    @State private var unarchiveConflict: Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(activeCategories) { category in
                    activeRow(category)

                    if category.persistentModelID != activeCategories.last?.persistentModelID {
                        Divider().padding(.leading, 36)
                    }
                }
                .onMove(perform: moveCategories)

                Divider()

                Button {
                    sheetMode = .add
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add category")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            if !archivedCategories.isEmpty {
                DisclosureGroup(isExpanded: $showArchivedDisclosure) {
                    VStack(spacing: 0) {
                        ForEach(archivedCategories) { category in
                            archivedRow(category)
                            if category.persistentModelID != archivedCategories.last?.persistentModelID {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 4)
                } label: {
                    Text("Show archived (\(archivedCategories.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(item: $sheetMode) { mode in
            CategoryEditSheet(mode: mode)
        }
        .alert("Name conflicts with an active category",
               isPresented: Binding(
                get: { unarchiveConflict != nil },
                set: { if !$0 { unarchiveConflict = nil } }
               )) {
            Button("Edit name", role: .none) {
                if let c = unarchiveConflict {
                    sheetMode = .edit(c)
                    unarchiveConflict = nil
                }
            }
            Button("Cancel", role: .cancel) { unarchiveConflict = nil }
        } message: {
            Text("Rename this category before unarchiving so it doesn't collide with an existing active category.")
        }
    }

    private func activeRow(_ category: Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Image(systemName: category.iconSymbol)
                .foregroundStyle(category.color)
                .frame(width: 24)

            Text(category.name)
                .font(.body)

            Spacer()

            Circle()
                .fill(category.color)
                .frame(width: 12, height: 12)

            Menu {
                Button {
                    sheetMode = .edit(category)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    archive(category)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func archivedRow(_ category: Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.iconSymbol)
                .foregroundStyle(category.color)
                .frame(width: 24)

            Text(category.name)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                attemptUnarchive(category)
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(0.7)
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var working = activeCategories
        working.move(fromOffsets: source, toOffset: destination)
        CategoryOrdering.normaliseOrder(of: working)
        try? modelContext.save()
    }

    private func archive(_ category: Category) {
        category.isArchived = true
        // Compact the active order range so a later add picks up a contiguous index.
        let remaining = activeCategories.filter {
            $0.persistentModelID != category.persistentModelID
        }
        CategoryOrdering.normaliseOrder(of: remaining)
        try? modelContext.save()
    }

    private func attemptUnarchive(_ category: Category) {
        let lowered = category.name.lowercased()
        let conflict = activeCategories.contains { $0.name.lowercased() == lowered }
        if conflict {
            unarchiveConflict = category
            return
        }
        category.isArchived = false
        // Append to the end of the active order.
        let nextOrder = (activeCategories.map(\.order).max() ?? -1) + 1
        category.order = nextOrder
        try? modelContext.save()
    }
}

extension CategoryEditSheet.Mode: Identifiable {
    public var id: String {
        switch self {
        case .add: return "add"
        case .edit(let category): return "edit-\(category.persistentModelID.hashValue)"
        }
    }
}
```

- [ ] **Step 14.3: Drop the stub from `SettingsView.swift`**

Open `TimeTracker2/Views/Settings/SettingsView.swift` and remove the `private struct CategoriesSection` stub at the bottom of the file. The `CategoriesSection()` call in `body` now resolves to the real implementation.

- [ ] **Step 14.4: Run tests**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test
```

Expected: all tests pass, including `CategoryReorderTests`.

- [ ] **Step 14.5: Commit**

```bash
git add TimeTracker2/Views/Settings/CategoriesSection.swift \
        TimeTracker2/Views/Settings/SettingsView.swift \
        TimeTracker2Tests/CategoryReorderTests.swift
git commit -m "Add Categories settings section with reorder, archive, and add"
```

---

### Task 15: Wire `SettingsView` into `ContentView`

**Files:**
- Modify: `TimeTracker2/ContentView.swift`
- Modify: `TimeTracker2/TimeTracker2App.swift`

- [ ] **Step 15.1: Update `ContentView.swift`**

Find:
```swift
                case .settings:
                    ReminderSettingsView()
```
Replace with:
```swift
                case .settings:
                    SettingsView()
```

- [ ] **Step 15.2: Update `TimeTracker2App.swift`'s `Settings { }` window**

The macOS `Settings { }` scene doesn't share the `WindowGroup`'s model container by default. `SettingsView`'s `@Query` declarations would crash without it, so attach `.modelContainer(_:)` to the Settings scene as well.

Find:
```swift
        Settings {
            // Replaced with SettingsView() in Task 14.
            ReminderSettingsView()
        }
```
Replace with:
```swift
        Settings {
            SettingsView()
                .frame(minWidth: 480, minHeight: 360)
        }
        .modelContainer(sharedModelContainer)
```

- [ ] **Step 15.3: Run build**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
```

Expected: success.

- [ ] **Step 15.4: Manual smoke check**

Run the app. Navigate to **Settings** in the tab bar. You should see:
- A "Categories" card listing the four seeded categories with reorder handles, an "+ Add category" row, and a "Show archived (0)" disclosure.
- A "Time Entry Reminder" card below it with the existing toggle and time picker.

Try:
1. Reorder two categories — confirm the order persists across app restart.
2. Add a new "Research" category with a teal swatch and the `chart.line.uptrend.xyaxis` icon. Confirm it appears at the bottom and shows up in the Tasks tab's `EditTaskSheet` picker.
3. Archive "Misc". Confirm it disappears from active sections and appears in the disclosure.
4. Open the Tasks tab and toggle "Show archived categories". Archived rows should appear dimmed with the "Archived" badge.

If any step misbehaves, fix it before continuing.

- [ ] **Step 15.5: Commit**

```bash
git add TimeTracker2/ContentView.swift TimeTracker2/TimeTracker2App.swift
git commit -m "Route Settings tab and Settings window to SettingsView"
```

---

### Task 16: Final cleanup — delete `TaskCategory.swift` and remove the legacy initializer

**Files:**
- Delete: `TimeTracker2/Models/TaskCategory.swift`
- Modify: `TimeTracker2/Models/TrackedTask.swift`
- Modify: `TimeTracker2/Views/Settings/ReminderSettingsView.swift` (optional)

- [ ] **Step 16.1: Confirm no remaining `TaskCategory` references**

```bash
grep -rn "TaskCategory" TimeTracker2 TimeTracker2Tests | grep -v "TaskCategory.swift"
```

Expected: only the legacy `convenience init(name:category:TaskCategory:…)` in `TrackedTask.swift` shows up.

- [ ] **Step 16.2: Remove the legacy initializer from `TrackedTask.swift`**

Delete this block from `TrackedTask.swift`:

```swift
    convenience init(name: String,
                     category: TaskCategory,
                     creationDate: Date = Date(),
                     isArchived: Bool = false) {
        self.init(name: name, category: nil as Category?,
                  creationDate: creationDate, isArchived: isArchived)
        self.categoryRawValue = category.rawValue
    }
```

If any test still calls this overload, update it to construct a `Category` model instead. (After Task 6, the only such caller was in `TimeTracker2Tests/TimeTracker2Tests.swift`, which we already migrated.)

- [ ] **Step 16.3: Delete `TaskCategory.swift`**

```bash
git rm TimeTracker2/Models/TaskCategory.swift
```

- [ ] **Step 16.4: Optionally collapse `ReminderSettingsView.swift`**

`ReminderSettingsView` is now a thin wrapper that nothing references. If a search confirms it has no callers, delete it:

```bash
grep -rn "ReminderSettingsView" TimeTracker2 TimeTracker2Tests
```

If the result is empty:

```bash
git rm TimeTracker2/Views/Settings/ReminderSettingsView.swift
```

If something still references it (it should not, after Task 15), leave it in place.

- [ ] **Step 16.5: Run build + tests**

```bash
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet build
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' -quiet test
```

Expected: build succeeds, all tests pass.

- [ ] **Step 16.6: Commit**

```bash
git add TimeTracker2/Models/TrackedTask.swift
git commit -m "Remove legacy TaskCategory enum and convenience initializer"
```

---

## Acceptance criteria recap (mapped to spec)

- ✅ New `Category` model with curated palettes — Task 1.
- ✅ `TrackedTask.category: Category?` relationship; `categoryRawValue` retained as deprecated — Task 4.
- ✅ Idempotent runtime migration with `categoriesMigratedV1` flag, four seeds, name-based back-link, "Misc" fallback, fresh-install path — Tasks 3 + 11.
- ✅ Existing tasks linked to the seeds; corrupt rows fall back to "Misc" — covered by `CategoryMigrationTests`.
- ✅ Settings tab with Categories section + Reminders below it — Tasks 12 + 14 + 15.
- ✅ `+ Add category` opens `CategoryEditSheet` with curated palettes and live preview — Tasks 13 + 14.
- ✅ Reorder writes back contiguous `order` — Tasks 14 + `CategoryReorderTests`.
- ✅ Archive hides from default views, surfaces dimmed under local toggles in Tasks/Summary — Tasks 9 + 10 + 14.
- ✅ Archived categories preserve historical entries; archive does not archive their tasks — Task 9 (tasks remain active), Task 14 (archive flips category only).
- ✅ Validation: non-empty trim + case-insensitive uniqueness scoped to non-archived — Task 2 + `CategoryValidationTests` + Task 14 (unarchive conflict alert).
- ✅ Picker for new/edited tasks queries active categories only — Tasks 7 + 9.
- ✅ DayCell, QuickEntry rows, TimeEntry rows render via `task.category?.color/iconSymbol` with safe fallback — Tasks 5 + 7 + 8.
- ✅ `SummaryViewModel` returns `[PersistentIdentifier: [TimeEntry]]`; exporters take `[Category]` — Task 6.
- ✅ Migration flag-gated, crash-safe, idempotent — Task 3.

## Out of scope (per spec)

- Removing the deprecated `categoryRawValue` column via a versioned schema migration.
- Letting users extend the curated palettes.
