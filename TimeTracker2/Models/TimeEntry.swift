//
//  TimeEntry.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import Foundation
import SwiftData

@Model
final class TimeEntry {
    var date: Date
    var duration: Double // Hours
    var notes: String
    var task: TrackedTask?
    var project: Project?

    init(date: Date, duration: Double, notes: String = "", task: TrackedTask? = nil, project: Project? = nil) {
        self.date = date
        self.duration = duration
        self.notes = notes
        self.task = task
        self.project = project
    }
}
