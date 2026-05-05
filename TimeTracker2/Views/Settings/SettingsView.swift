//
//  SettingsView.swift
//  TimeTracker2
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CategoriesSection()
                RemindersSection()
            }
            .padding()
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self, Project.self,
                              DayOff.self, Category.self], inMemory: true)
}

private struct CategoriesSection: View {
    var body: some View {
        Text("Categories — TODO Task 14")
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
