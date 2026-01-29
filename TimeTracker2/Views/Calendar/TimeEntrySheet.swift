//
//  TimeEntrySheet.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import SwiftUI
import SwiftData

struct TimeEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allEntries: [TimeEntry]
    
    let date: Date
    let tasks: [TrackedTask]
    
    @State private var selectedTask: TrackedTask?
    @State private var duration: Double = 1.0
    @State private var notes: String = ""
    @State private var searchText: String = ""
    @State private var selectedCategory: TaskCategory?
    @State private var showingNewTaskSheet: Bool = false
    @State private var entryToEdit: TimeEntry?
    @State private var showingEditSheet: Bool = false
    
    private var entriesForDate: [TimeEntry] {
        let calendar = Calendar.current
        return allEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    private var filteredTasks: [TrackedTask] {
        var filtered = tasks.filter { !$0.isArchived }

        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return filtered.sorted { $0.entries.count > $1.entries.count }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(dateString)
                        .font(.headline)
                }
                
                if !entriesForDate.isEmpty {
                    Section("Logged Time") {
                        ForEach(entriesForDate) { entry in
                            ExistingEntryRow(entry: entry) {
                                entryToEdit = entry
                                showingEditSheet = true
                            }
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
                
                Section("Add New Entry") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as TaskCategory?)
                        ForEach(TaskCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category as TaskCategory?)
                        }
                    }
                    
                    TextField("Search tasks...", text: $searchText)
                    
                    if filteredTasks.isEmpty {
                        ContentUnavailableView {
                            Label("No Tasks", systemImage: "tray")
                        } description: {
                            Text("Create a new task to get started")
                        } actions: {
                            Button("Create Task") {
                                showingNewTaskSheet = true
                            }
                        }
                    } else {
                        ForEach(filteredTasks) { task in
                            TaskRow(task: task, isSelected: selectedTask?.id == task.id) {
                                selectedTask = task
                            }
                        }
                        Button {
                            showingNewTaskSheet = true
                        } label: {
                            Label("Create New Task", systemImage: "plus.circle")
                        }
                    }
                }
                
                if selectedTask != nil {
                    Section("Time") {
                        HStack {
                            Text("Hours")
                            Spacer()
                            TextField("Hours", value: $duration, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack(spacing: 8) {
                            ForEach([0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { hours in
                                Button(String(format: hours == floor(hours) ? "%.0fh" : "%.1fh", hours)) {
                                    duration = hours
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    
                    Section("Notes") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 60)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Log Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("New Task") {
                        showingNewTaskSheet = true
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Entry") {
                        saveEntry()
                    }
                    .disabled(selectedTask == nil || duration <= 0)
                }
            }
            .sheet(isPresented: $showingNewTaskSheet) {
                NewTaskSheet { newTask in
                    selectedTask = newTask
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let entry = entryToEdit {
                    EditEntrySheet(entry: entry, tasks: tasks)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 550)
    }
    
    private func saveEntry() {
        guard let task = selectedTask else { return }
        
        let entry = TimeEntry(date: date, duration: duration, notes: notes, task: task)
        modelContext.insert(entry)
        
        selectedTask = nil
        duration = 1.0
        notes = ""
    }
    
    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            let entry = entriesForDate[index]
            modelContext.delete(entry)
        }
    }
}

struct ExistingEntryRow: View {
    let entry: TimeEntry
    let onEdit: () -> Void
    
    var body: some View {
        Button(action: onEdit) {
            HStack {
                if let task = entry.task {
                    Image(systemName: task.category.icon)
                        .foregroundStyle(task.category.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name)
                            .font(.body)
                        
                        if !entry.notes.isEmpty {
                            Text(entry.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("Unknown Task")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(String(format: "%.1fh", entry.duration))
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EditEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let entry: TimeEntry
    let tasks: [TrackedTask]
    
    @State private var selectedTask: TrackedTask?
    @State private var duration: Double
    @State private var notes: String
    @State private var showingDeleteConfirmation: Bool = false
    
    private var editableTaskList: [TrackedTask] {
        var list = tasks.filter { !$0.isArchived }
        if let current = entry.task, current.isArchived, !list.contains(where: { $0.id == current.id }) {
            list.insert(current, at: 0)
        }
        return list
    }

    init(entry: TimeEntry, tasks: [TrackedTask]) {
        self.entry = entry
        self.tasks = tasks
        _selectedTask = State(initialValue: entry.task)
        _duration = State(initialValue: entry.duration)
        _notes = State(initialValue: entry.notes)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    ForEach(editableTaskList) { task in
                        TaskRow(task: task, isSelected: selectedTask?.id == task.id) {
                            selectedTask = task
                        }
                    }
                }
                
                Section("Time") {
                    HStack {
                        Text("Hours")
                        Spacer()
                        TextField("Hours", value: $duration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack(spacing: 8) {
                        ForEach([0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { hours in
                            Button(String(format: hours == floor(hours) ? "%.0fh" : "%.1fh", hours)) {
                                duration = hours
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Entry", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(selectedTask == nil || duration <= 0)
                }
            }
            .confirmationDialog("Delete Entry", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteEntry()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this time entry? This cannot be undone.")
            }
        }
        .frame(minWidth: 400, minHeight: 450)
    }
    
    private func saveChanges() {
        entry.task = selectedTask
        entry.duration = duration
        entry.notes = notes
        dismiss()
    }
    
    private func deleteEntry() {
        modelContext.delete(entry)
        dismiss()
    }
}

struct TaskRow: View {
    let task: TrackedTask
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: task.category.icon)
                    .foregroundStyle(task.category.color)
                
                Text(task.name)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NewTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let onTaskCreated: (TrackedTask) -> Void
    
    @State private var name: String = ""
    @State private var category: TaskCategory = .misc
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task Name", text: $name)
                    
                    Picker("Category", selection: $category) {
                        ForEach(TaskCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTask()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }
    
    private func createTask() {
        let task = TrackedTask(name: name, category: category)
        modelContext.insert(task)
        onTaskCreated(task)
        dismiss()
    }
}

#Preview {
    TimeEntrySheet(date: Date(), tasks: [])
        .modelContainer(for: [TrackedTask.self, TimeEntry.self], inMemory: true)
}
