//
//  DayOff.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2026-01-29.
//

import Foundation
import SwiftData

@Model
final class DayOff {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}
