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
