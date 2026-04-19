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
