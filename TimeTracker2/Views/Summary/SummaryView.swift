//
//  SummaryView.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import SwiftUI
import SwiftData

struct SummaryView: View {
    @Query private var entries: [TimeEntry]
    
    @State private var viewModel = SummaryViewModel()
    @State private var expandedCategories: Set<TaskCategory> = Set(TaskCategory.allCases)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Month navigation header
                monthHeader
                
                // Total hours card
                totalHoursCard
                
                // Category sections
                categoryCards
            }
            .padding()
        }
    }
    
    private var monthHeader: some View {
        HStack {
            Button(action: viewModel.previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(viewModel.monthYearString)
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: viewModel.nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var totalHoursCard: some View {
        VStack(spacing: 8) {
            Text("Total Hours")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text(String(format: "%.1f", viewModel.totalHoursForMonth(entries)))
                .font(.system(size: 48, weight: .bold, design: .rounded))
            
            Text("hours logged this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var categoryCards: some View {
        VStack(spacing: 12) {
            ForEach(TaskCategory.allCases) { category in
                let categoryHours = viewModel.totalHoursForCategory(category, entries: entries)
                
                if categoryHours > 0 {
                    CategoryCard(
                        category: category,
                        totalHours: categoryHours,
                        taskHours: viewModel.taskHoursForCategory(category, entries: entries),
                        isExpanded: expandedCategories.contains(category)
                    ) {
                        toggleCategory(category)
                    }
                }
            }
        }
    }
    
    private func toggleCategory(_ category: TaskCategory) {
        withAnimation {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }
}

struct CategoryCard: View {
    let category: TaskCategory
    let totalHours: Double
    let taskHours: [(task: TrackedTask, hours: Double)]
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: onToggle) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.title2)
                        .foregroundStyle(category.color)
                        .frame(width: 32)
                    
                    Text(category.displayName)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(String(format: "%.1fh", totalHours))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded task list
            if isExpanded && !taskHours.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(taskHours, id: \.task.id) { item in
                        TaskHoursRow(taskName: item.task.name, hours: item.hours, color: category.color)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TaskHoursRow: View {
    let taskName: String
    let hours: Double
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 8, height: 8)
            
            Text(taskName)
                .font(.subheadline)
            
            Spacer()
            
            Text(String(format: "%.1fh", hours))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }
}

#Preview {
    SummaryView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self], inMemory: true)
}
