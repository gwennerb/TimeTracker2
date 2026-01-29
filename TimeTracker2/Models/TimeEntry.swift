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
    
    init(date: Date, duration: Double, notes: String = "", task: TrackedTask? = nil) {
        self.date = date
        self.duration = duration
        self.notes = notes
        self.task = task
    }
}
