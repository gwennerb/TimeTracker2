//
//  ContentView.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case calendar = "Calendar"
    case tasks = "Tasks"
    case summary = "Summary"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .calendar:
            return "calendar"
        case .tasks:
            return "list.bullet"
        case .summary:
            return "chart.bar.fill"
        case .settings:
            return "bell.badge"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .calendar
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            Group {
                switch selectedTab {
                case .calendar:
                    CalendarView()
                case .tasks:
                    TasksView()
                case .summary:
                    SummaryView()
                case .settings:
                    ReminderSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom glass-styled tab bar
            GlassTabBar(selectedTab: $selectedTab)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct GlassTabBar: View {
    @Binding var selectedTab: AppTab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabButton(tab: tab, isSelected: selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
}

struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .medium))
                
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self], inMemory: true)
}
