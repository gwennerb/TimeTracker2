# User-Configurable Categories — Design

**Date:** 2026-05-05
**Status:** Approved (pending implementation)

## Goal

Replace the hardcoded `TaskCategory` enum (`App`, `Portal`, `Back Office`, `Misc`) with user-managed categories. Users can add, edit (name / color / icon), reorder, and archive categories. Existing tasks and historical entries remain intact through the transition.

## Non-Goals

- Free-form color picking. Colors come from a curated palette to preserve glass-morphism legibility.
- Free-form SF Symbol search. Icons come from a curated set.
- Hard delete. Archive is the only destructive action; archived categories preserve their historical entries.
- Per-category permissions (system vs user). All categories — including the four seeded defaults — are editable, archivable, and reorderable.

## User-facing summary

- Settings tab gains a **Categories** section alongside the existing Reminders.
- Each category row shows icon + name + color swatch, with a drag handle for reorder and a `⋯` menu for Edit / Archive.
- "+ Add category" opens a sheet with a name field, a curated color palette (10 swatches), a curated SF Symbol grid (~20 icons), and a live preview row.
- Archived categories are hidden behind a `Show archived (n)` disclosure with un-archive controls.
- Both the **Summary** and **Tasks** tabs get their own local "Show archived" toggle. Off by default — sections for archived categories are hidden. On — they appear dimmed with an "Archived" badge so historical hours and tasks stay reachable. Each tab's toggle is independent (in-memory `@State`, not persisted).
- Archiving a category does **not** archive its tasks. Tasks under an archived category remain active records; they're just hidden from the default Tasks/Summary views until the local toggle is on. New tasks can't be assigned to an archived category (it doesn't appear in pickers).
- For existing installs, the four current categories appear unchanged on first launch after upgrade.

## Data model

New SwiftData model:

```swift
@Model
final class Category {
    var name: String
    var colorName: String      // key into Category.colorPalette
    var iconSymbol: String     // SF Symbol name from Category.iconPalette
    var order: Int             // manual sort, 0-based, contiguous
    var isArchived: Bool
    var creationDate: Date

    @Relationship(deleteRule: .nullify, inverse: \TrackedTask.category)
    var tasks: [TrackedTask]

    init(name: String, colorName: String, iconSymbol: String,
         order: Int, isArchived: Bool = false, creationDate: Date = Date()) {
        self.name = name
        self.colorName = colorName
        self.iconSymbol = iconSymbol
        self.order = order
        self.isArchived = isArchived
        self.creationDate = creationDate
        self.tasks = []
    }
}
```

Category exposes computed helpers:

```swift
extension Category {
    var color: Color { Category.colorPalette[colorName] ?? .gray }
    var displayName: String { name }   // parity with old TaskCategory API surface

    static let colorPalette: [String: Color] = [
        "blue": .blue, "purple": .purple, "orange": .orange, "gray": .gray,
        "green": .green, "pink": .pink, "red": .red, "yellow": .yellow,
        "teal": .teal, "indigo": .indigo,
    ]

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

`TrackedTask` gains an optional `Category` relationship and loses its computed `category: TaskCategory`:

```swift
@Model
final class TrackedTask {
    var name: String
    var categoryRawValue: String     // DEPRECATED: kept one release as migration fallback; remove in follow-up
    var creationDate: Date
    var isArchived: Bool

    @Relationship(deleteRule: .nullify)
    var category: Category?

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.task)
    var entries: [TimeEntry]
}
```

Files deleted: `Models/TaskCategory.swift`.

## Migration

A one-time runtime migration runs on app launch, gated by `UserDefaults.standard.bool(forKey: "categoriesMigratedV1")`.

### Order of operations

1. **SwiftData lightweight schema migration (automatic):** introduces the `Category` table and adds optional `category: Category?` to `TrackedTask`. `categoryRawValue` stays. No data is rewritten yet.
2. **Runtime migration runs:**
   1. If `categoriesMigratedV1` is set, skip.
   2. Fetch existing `Category` rows. If none, insert four seeds:
      - `App` / `blue` / `app.fill` / order `0`
      - `Portal` / `purple` / `globe` / order `1`
      - `Back Office` / `orange` / `building.2.fill` / order `2`
      - `Misc` / `gray` / `ellipsis.circle.fill` / order `3`
   3. Fetch all `TrackedTask` rows where `category == nil`. For each, look up the seed by `name == task.categoryRawValue` and assign. If no match (corrupt data), assign the `Misc` seed.
   4. Save the context. Set `categoriesMigratedV1 = true`.

### Properties

- **Idempotent.** If the flag is wiped and migration re-runs, existing seeds are reused (the empty-table check prevents duplicates) and only nil-category tasks get linked.
- **Crash-safe.** A mid-migration crash leaves the flag unset, so it retries on next launch.
- **Fresh installs** also hit the empty-table branch and end up with the same 4 seeds — no separate seeding code path.

`categoryRawValue` is preserved (read-only) for one release as a safety net. A follow-up release deletes the column via a versioned schema migration once we're confident the runtime migration has landed for all users.

## Settings UI

`Views/Settings/ReminderSettingsView.swift` is renamed and refactored into:

```
Views/Settings/
├── SettingsView.swift           (host: ScrollView of section cards)
├── RemindersSection.swift       (existing reminder body, lifted)
├── CategoriesSection.swift      (new)
└── CategoryEditSheet.swift      (new — add and edit, single sheet)
```

`ContentView` switches `case .settings:` from `ReminderSettingsView()` to `SettingsView()`.

### CategoriesSection

```
┌─ Categories ───────────────────────────────────┐
│  ≡ [icon] App              [● blue]      ⋯     │
│  ≡ [icon] Portal           [● purple]    ⋯     │
│  ≡ [icon] Back Office      [● orange]    ⋯     │
│  ≡ [icon] Misc             [● gray]      ⋯     │
│                                                 │
│  [+ Add category]                               │
│                                                 │
│  ▸ Show archived (0)                            │
└─────────────────────────────────────────────────┘
```

- Active categories rendered by `List` with `.onMove` writing back to `order: Int`. After a reorder, the `order` values are normalized to be contiguous (`0..<n`).
- Each row's `⋯` menu has **Edit** and **Archive**.
- "+ Add category" presents `CategoryEditSheet` in create mode.
- Archived categories live behind a `DisclosureGroup` that's collapsed by default. Each archived row shows the icon and name dimmed, with an **Unarchive** button.

### CategoryEditSheet

- Live preview row at the top: `Image(systemName: chosenIcon).foregroundStyle(chosenColor)` next to the typed name.
- `TextField` for name.
- Color palette: horizontal `LazyVGrid` of 10 swatches; selection highlighted with a ring.
- Icon palette: `LazyVGrid` of ~20 SF Symbols; selection highlighted with a ring.
- **Cancel** / **Save** buttons. Save disabled until validation passes.

### Validation

- Name non-empty after trimming.
- Name unique (case-insensitive) among **non-archived** categories. Archived categories don't conflict; un-archiving an archived category whose name now collides with an active one prompts the user to rename.

## View / ViewModel changes

The change is mostly mechanical: replace `TaskCategory` (enum) with `Category` (model) and replace `TaskCategory.allCases` with a `@Query` of active categories sorted by `order`.

| File | Change |
| --- | --- |
| `Models/TaskCategory.swift` | Deleted. |
| `Models/TrackedTask.swift` | Drop computed `category: TaskCategory`. Add `category: Category?` relationship. Init takes `category: Category`. Keep `categoryRawValue` as deprecated. |
| `ViewModels/SummaryViewModel.swift` | `entriesByCategory` returns `[Category: [TimeEntry]]` (Category is Hashable via `PersistentIdentifier`). Replace `TaskCategory.allCases` loops with an injected `[Category]` parameter — callers pass the `@Query` result. `totalHoursForCategory(_:)`, `taskHoursForCategory(_:)`, exporters all switch type. |
| `ViewModels/CalendarViewModel.swift` | `categoriesForDate` returns `Set<Category>`. |
| `Views/Summary/SummaryView.swift` | Adds `@Query` for active categories sorted by `order`. Adds local `@State showArchived: Bool` and a toolbar toggle; when on, an additional `@Query` of archived categories appends them rendered with `.opacity(0.5)` and an "Archived" badge. `expandedCategories: Set<TaskCategory>` becomes `Set<PersistentIdentifier>`. |
| `Views/Tasks/TasksView.swift` | Group active tasks by `task.category`. Iterate over the active-category `@Query` for section order. Edit-task picker queries active categories only (archived categories are not selectable for new/edited tasks). Adds local `@State showArchived: Bool` and toolbar toggle; when on, sections for archived categories also render (dimmed) with their tasks. |
| `Views/Calendar/TimeEntrySheet.swift` | Category filter and new-task picker both query active categories. |
| `Views/Calendar/CalendarView.swift` | `DayCell` `categories: Set<TaskCategory>` becomes `Set<Category>`. Color rendering goes through `category.color`. |
| `Views/QuickEntry/QuickEntryView.swift` | Reads `task.category?.iconSymbol` / `task.category?.color`. After migration runs, `category` is non-nil for every existing task, but the optional must still be unwrapped — fall back to `"questionmark.circle"` / `.gray` if nil (defensive; should not trigger in practice). |
| `ContentView.swift` | `.settings` case routes to `SettingsView()`. |
| `TimeTracker2App.swift` | Add `Category.self` to the `ModelContainer` schema. Kick off the runtime migration after the container is ready. |

## Testing

Existing `xcodebuild test` continues to run. New unit tests:

- **Migration tests** (`CategoryMigrationTests`):
  - Fresh install: seeds appear, all 4 with correct names/colors/icons/order, flag is set.
  - Existing install with tasks across all 4 enum values: each task links to the matching seed by name.
  - Existing install with a task whose `categoryRawValue` doesn't match any seed: linked to `Misc`.
  - Idempotent: running migration twice doesn't duplicate seeds and doesn't re-link already-linked tasks.
- **Validation tests** (`CategoryValidationTests`):
  - Name non-empty after trim.
  - Name uniqueness is case-insensitive and scoped to non-archived categories.
- **Reorder test:** moving a category updates `order` to a contiguous `0..<n` sequence.

## Open follow-ups (out of scope for this spec)

- Remove the deprecated `TrackedTask.categoryRawValue` column via a versioned schema migration in a follow-up release.
- Consider exposing the curated palette as user-extendable in a future spec if the curated set proves insufficient.
