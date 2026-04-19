//
//  ProjectMigration.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2026-04-19.
//

import Foundation
import SwiftData

enum ProjectMigration {
    static let defaultProjectName = "Varberg"

    @MainActor
    static func ensureSeed(_ context: ModelContext) {
        let existingProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard existingProjects.isEmpty else { return }

        let seed = Project(name: defaultProjectName)
        context.insert(seed)

        let orphanEntries = (try? context.fetch(FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.project == nil }
        ))) ?? []

        for entry in orphanEntries {
            entry.project = seed
        }

        try? context.save()
    }
}
