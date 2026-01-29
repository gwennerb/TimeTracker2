# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a macOS SwiftUI app built with Xcode. No external package dependencies.

```bash
# Build
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' build

# Run tests
xcodebuild -scheme TimeTracker2 -destination 'platform=macOS' test
```

- Deployment target: macOS 26.1
- Swift 5.0, Xcode 26.1.1
- Bundle ID: `asa.TimeTracker2`

## Architecture

MVVM pattern with SwiftData persistence. No external dependencies — only SwiftUI, SwiftData, and Foundation.

**Models** (`Models/`): SwiftData `@Model` classes defining persistence schema.
- `TrackedTask` — a named task with a category and one-to-many cascade relationship to `TimeEntry`
- `TimeEntry` — a time log with date, duration (hours as Double), optional notes, linked to a task
- `TaskCategory` — enum (App, Portal, Back Office, Misc) with associated colors and SF Symbols

**ViewModels** (`ViewModels/`): `@Observable` classes containing date math, filtering, and aggregation logic.
- `CalendarViewModel` — calendar grid generation (ISO8601 Monday-based weeks), month navigation, per-date entry filtering
- `SummaryViewModel` — monthly hour totals, category/task grouping and sorting

**Views** (`Views/`): SwiftUI views using `@Query` for data fetching and `@Environment(\.modelContext)` for mutations.
- `ContentView` — tab bar (Calendar / Summary) with glass-morphism styling, min window 600×500
- `CalendarView` — monthly grid with DayCell showing category dots and hours
- `TimeEntrySheet` — complex sheet containing entry creation/editing, task search, new task creation, and delete confirmation (5 nested view components)
- `SummaryView` — expandable category cards with per-task hour breakdowns

**App entry** (`TimeTracker2App.swift`): Sets up the `ModelContainer` with `TrackedTask` and `TimeEntry` schemas.

## Key Patterns

- Categories use a `categoryRawValue: String` stored property with a computed `category: TaskCategory` property for type safety
- Duration presets: 0.5, 1, 2, 4, 8 hours
- Calendar uses `Calendar(identifier: .iso8601)` with Monday as first weekday
- Glass-morphism UI throughout (`.ultraThinMaterial` backgrounds)
- App sandbox enabled, read-only file access, MainActor isolation enforced
