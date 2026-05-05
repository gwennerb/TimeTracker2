//
//  Category.swift
//  TimeTracker2
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Category {
    var name: String
    var colorName: String
    var iconSymbol: String
    var order: Int
    var isArchived: Bool
    var creationDate: Date

    @Relationship(deleteRule: .nullify, inverse: \TrackedTask.category)
    var tasks: [TrackedTask]

    init(name: String,
         colorName: String,
         iconSymbol: String,
         order: Int,
         isArchived: Bool = false,
         creationDate: Date = Date()) {
        self.name = name
        self.colorName = colorName
        self.iconSymbol = iconSymbol
        self.order = order
        self.isArchived = isArchived
        self.creationDate = creationDate
        self.tasks = []
    }
}

extension Category {
    /// Resolved SwiftUI colour for the stored palette key. Falls back to `.gray`
    /// so an out-of-band value (e.g. seeded by a future build) never crashes.
    var color: Color {
        Category.colorPalette[colorName] ?? .gray
    }

    /// Curated palette. Keys are stored on disk; do not rename keys without a migration.
    static let colorPalette: [String: Color] = [
        "blue": .blue,
        "purple": .purple,
        "orange": .orange,
        "gray": .gray,
        "green": .green,
        "pink": .pink,
        "red": .red,
        "yellow": .yellow,
        "teal": .teal,
        "indigo": .indigo,
    ]

    /// Display order for swatches in the edit sheet.
    static let colorPaletteOrder: [String] = [
        "blue", "purple", "orange", "gray", "green",
        "pink", "red", "yellow", "teal", "indigo",
    ]

    /// Curated SF Symbol set surfaced in the icon picker.
    static let iconPalette: [String] = [
        "app.fill", "globe", "building.2.fill", "ellipsis.circle.fill",
        "doc.text.fill", "hammer.fill", "bubble.left.fill", "calendar",
        "paintbrush.fill", "gearshape.fill", "terminal.fill", "gauge",
        "megaphone.fill", "chart.line.uptrend.xyaxis", "sparkles",
        "lock.fill", "person.2.fill", "lightbulb.fill",
        "square.and.pencil", "tray.full.fill",
    ]
}
