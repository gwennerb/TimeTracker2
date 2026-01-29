//
//  TaskCategory.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import SwiftUI

enum TaskCategory: String, Codable, CaseIterable, Identifiable {
    case app = "App"
    case portal = "Portal"
    case backOffice = "Back Office"
    case misc = "Misc"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var color: Color {
        switch self {
        case .app:
            return .blue
        case .portal:
            return .purple
        case .backOffice:
            return .orange
        case .misc:
            return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .app:
            return "app.fill"
        case .portal:
            return "globe"
        case .backOffice:
            return "building.2.fill"
        case .misc:
            return "ellipsis.circle.fill"
        }
    }
}
