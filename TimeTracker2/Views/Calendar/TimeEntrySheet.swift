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
    @Query private var daysOff: [DayOff]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]

    let date: Date
    let tasks: [TrackedTask]

    @State private var selectedTask: TrackedTask?
    @State private var selectedProject: Project?
    @State private var duration: Double = 1.0
    @State private var notes: String = ""
    @State private var searchText: String = ""
    @State private var selectedCategory: Category?
    @State private var showingNewTaskSheet: Bool = false
    @State private var showingNewProjectSheet: Bool = false
    @State private var entryToEdit: TimeEntry?
    @State private var showingEditSheet: Bool = false
    @State private var showingRepeatConfirmation: Bool = false

    private var entriesForDate: [TimeEntry] {
        let calendar = Calendar.current
        return allEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private var activeProjects: [Project] {
        allProjects.filter { !$0.isArchived }
    }

    private var filteredTasks: [TrackedTask] {
        var filtered = tasks.filter { !$0.isArchived }

        if let category = selectedCategory {
            filtered = filtered.filter { $0.category?.persistentModelID == category.persistentModelID }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return filtered.sortedByRecency()
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
                    Toggle("Day off", isOn: Binding(
                        get: { isDayOff },
                        set: { newValue in toggleDayOff(newValue) }
                    ))
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
                    HStack {
                        Picker("Project", selection: $selectedProject) {
                            Text("Select project…").tag(nil as Project?)
                            ForEach(activeProjects) { project in
                                Text(project.name).tag(project as Project?)
                            }
                        }
                        Button {
                            showingNewProjectSheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Create new project")
                    }

                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as Category?)
                        ForEach(activeCategories) { category in
                            Label(category.name, systemImage: category.iconSymbol)
                                .tag(category as Category?)
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

                if mostRecentPriorDay != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if entriesForDate.isEmpty {
                                performRepeatPreviousDay()
                            } else {
                                showingRepeatConfirmation = true
                            }
                        } label: {
                            Label("Repeat Previous Day", systemImage: "arrow.clockwise")
                        }
                        .help("Duplicate entries from the most recent prior day with logged time")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Entry") {
                        saveEntry()
                    }
                    .disabled(selectedTask == nil || selectedProject == nil || duration <= 0)
                }
            }
            .sheet(isPresented: $showingNewTaskSheet) {
                NewTaskSheet { newTask in
                    selectedTask = newTask
                }
            }
            .sheet(isPresented: $showingNewProjectSheet) {
                NewProjectSheet { newProject in
                    selectedProject = newProject
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let entry = entryToEdit {
                    EditEntrySheet(entry: entry, tasks: tasks)
                }
            }
            .confirmationDialog(
                "This day already has \(entriesForDate.count) entr\(entriesForDate.count == 1 ? "y" : "ies"). Append the previous day's entries on top?",
                isPresented: $showingRepeatConfirmation
            ) {
                Button("Append") { performRepeatPreviousDay() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .frame(minWidth: 450, minHeight: 550)
    }

    private var mostRecentPriorDay: Date? {
        EntryDuplicator.mostRecentPriorDay(before: date, in: allEntries)
    }

    private func performRepeatPreviousDay() {
        guard let source = mostRecentPriorDay else { return }
        EntryDuplicator.duplicateDay(from: source, to: date, among: allEntries, in: modelContext)
    }

    private var isDayOff: Bool {
        let calendar = Calendar.current
        return daysOff.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func toggleDayOff(_ on: Bool) {
        let calendar = Calendar.current
        if on {
            modelContext.insert(DayOff(date: calendar.startOfDay(for: date)))
        } else if let existing = daysOff.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            modelContext.delete(existing)
        }
    }

    private func saveEntry() {
        guard let task = selectedTask, let project = selectedProject else { return }

        let entry = TimeEntry(date: date, duration: duration, notes: notes, task: task, project: project)
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
                    Image(systemName: task.category?.iconSymbol ?? "questionmark.circle")
                        .foregroundStyle(task.category?.color ?? .gray)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(task.name)
                                .font(.body)

                            if let project = entry.project {
                                Text(project.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                        }

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
    @Query(sort: \Project.name) private var allProjects: [Project]

    let entry: TimeEntry
    let tasks: [TrackedTask]

    @State private var selectedTask: TrackedTask?
    @State private var selectedProject: Project?
    @State private var duration: Double
    @State private var notes: String
    @State private var showingDeleteConfirmation: Bool = false

    private var editableTaskList: [TrackedTask] {
        var list = tasks.filter { !$0.isArchived }.sortedByRecency()
        if let current = entry.task, current.isArchived, !list.contains(where: { $0.id == current.id }) {
            list.insert(current, at: 0)
        }
        return list
    }

    private var editableProjectList: [Project] {
        var list = allProjects.filter { !$0.isArchived }
        if let current = entry.project, current.isArchived, !list.contains(where: { $0.id == current.id }) {
            list.insert(current, at: 0)
        }
        return list
    }

    init(entry: TimeEntry, tasks: [TrackedTask]) {
        self.entry = entry
        self.tasks = tasks
        _selectedTask = State(initialValue: entry.task)
        _selectedProject = State(initialValue: entry.project)
        _duration = State(initialValue: entry.duration)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    Picker("Project", selection: $selectedProject) {
                        Text("Select project…").tag(nil as Project?)
                        ForEach(editableProjectList) { project in
                            Text(project.name).tag(project as Project?)
                        }
                    }
                }

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
                    .disabled(selectedTask == nil || selectedProject == nil || duration <= 0)
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
        .frame(minWidth: 400, minHeight: 500)
    }

    private func saveChanges() {
        entry.task = selectedTask
        entry.project = selectedProject
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
                Image(systemName: task.category?.iconSymbol ?? "questionmark.circle")
                    .foregroundStyle(task.category?.color ?? .gray)

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

    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]

    let onTaskCreated: (TrackedTask) -> Void

    @State private var name: String = ""
    @State private var selectedCategory: Category?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task Name", text: $name)

                    Picker("Category", selection: $selectedCategory) {
                        Text("Select a category…").tag(nil as Category?)
                        ForEach(activeCategories) { category in
                            Label(category.name, systemImage: category.iconSymbol)
                                .tag(category as Category?)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createTask() }
                        .disabled(name.isEmpty || selectedCategory == nil)
                }
            }
            .onAppear { selectedCategory = activeCategories.first }
        }
        .frame(minWidth: 300, minHeight: 200)
    }

    private func createTask() {
        guard let category = selectedCategory else { return }
        let task = TrackedTask(name: name, category: category)
        modelContext.insert(task)
        onTaskCreated(task)
        dismiss()
    }
}

#Preview {
    TimeEntrySheet(date: Date(), tasks: [])
        .modelContainer(for: [TrackedTask.self, TimeEntry.self, DayOff.self, Project.self], inMemory: true)
}
