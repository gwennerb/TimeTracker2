//
//  CalendarView.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [TimeEntry]
    @Query(filter: #Predicate<TrackedTask> { !$0.isArchived }) private var tasks: [TrackedTask]
    
    @State private var viewModel = CalendarViewModel()
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    
    var body: some View {
        VStack(spacing: 16) {
            // Month navigation header
            monthHeader
            
            // Weekday headers
            weekdayHeaders
            
            // Calendar grid
            calendarGrid
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $viewModel.showingEntrySheet) {
            if let selectedDate = viewModel.selectedDayForEntry {
                TimeEntrySheet(date: selectedDate, tasks: tasks)
            }
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
    
    private var weekdayHeaders: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }
    
    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(viewModel.currentMonthDates, id: \.self) { date in
                DayCell(
                    date: date,
                    isCurrentMonth: viewModel.isCurrentMonth(date),
                    isToday: viewModel.isToday(date),
                    dayNumber: viewModel.dayNumber(date),
                    categories: viewModel.categoriesForDate(date, entries: entries),
                    totalHours: viewModel.totalHoursForDate(date, entries: entries)
                ) {
                    viewModel.selectDay(date)
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let dayNumber: String
    let categories: Set<TaskCategory>
    let totalHours: Double
    let onTap: () -> Void
    
    private var foregroundColor: Color {
        if !isCurrentMonth {
            return .gray.opacity(0.4)
        } else if isToday {
            return .white
        } else {
            return .primary
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(dayNumber)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(foregroundColor)
                
                if !categories.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(Array(categories).prefix(3), id: \.self) { category in
                            Circle()
                                .fill(category.color)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                
                if totalHours > 0 {
                    Text(String(format: "%.1fh", totalHours))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue)
                } else if isCurrentMonth {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self], inMemory: true)
}
