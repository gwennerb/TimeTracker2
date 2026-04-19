//
//  Project.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2026-04-19.
//

import Foundation
import SwiftData

@Model
final class Project {
    var name: String
    var creationDate: Date
    var isArchived: Bool

    @Relationship(deleteRule: .nullify, inverse: \TimeEntry.project)
    var entries: [TimeEntry]

    init(name: String, creationDate: Date = Date(), isArchived: Bool = false) {
        self.name = name
        self.creationDate = creationDate
        self.isArchived = isArchived
        self.entries = []
    }
}
