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
