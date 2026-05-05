//
//  TimeTracker2App.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
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
            SettingsView()
                .frame(minWidth: 480, minHeight: 360)
        }
        .modelContainer(sharedModelContainer)
    }
}
