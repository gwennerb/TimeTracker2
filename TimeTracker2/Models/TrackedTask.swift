//
//  TrackedTask.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import Foundation
import SwiftData

@Model
final class TrackedTask {
    var name: String
    var categoryRawValue: String
    var creationDate: Date
    var isArchived: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.task)
    var entries: [TimeEntry]
    
    var category: TaskCategory {
        get { TaskCategory(rawValue: categoryRawValue) ?? .misc }
        set { categoryRawValue = newValue.rawValue }
    }
    
    init(name: String, category: TaskCategory, creationDate: Date = Date(), isArchived: Bool = false) {
        self.name = name
        self.categoryRawValue = category.rawValue
        self.creationDate = creationDate
        self.isArchived = isArchived
        self.entries = []
    }
}
