//
//  TasksView.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import SwiftUI
import SwiftData

struct TasksView: View {
    @Query(sort: \TrackedTask.name) private var allTasks: [TrackedTask]
    @State private var showArchived: Bool = false
    @State private var editingTask: TrackedTask?

    private var activeTasks: [TrackedTask] {
        allTasks.filter { !$0.isArchived }
    }

    private var archivedTasks: [TrackedTask] {
        allTasks.filter { $0.isArchived }
    }

    private var groupedActiveTasks: [(TaskCategory, [TrackedTask])] {
        let grouped = Dictionary(grouping: activeTasks) { $0.category }
        return TaskCategory.allCases.compactMap { category in
            guard let tasks = grouped[category], !tasks.isEmpty else { return nil }
            return (category, tasks.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Active tasks grouped by category
                ForEach(groupedActiveTasks, id: \.0) { category, tasks in
                    categorySection(category: category, tasks: tasks, archived: false)
                }

                if activeTasks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "tray")
                    } description: {
                        Text("Tasks created when logging time will appear here.")
                    }
                }

                // Archived section
                if !archivedTasks.isEmpty {
                    archivedSection
                }
            }
            .padding()
        }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task)
        }
    }

    private func categorySection(category: TaskCategory, tasks: [TrackedTask], archived: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(category.displayName, systemImage: category.icon)
                .font(.headline)
                .foregroundStyle(category.color)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    taskRow(task: task, archived: archived)

                    if task.id != tasks.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func taskRow(task: TrackedTask, archived: Bool) -> some View {
        Button {
            editingTask = task
        } label: {
            HStack {
                Image(systemName: task.category.icon)
                    .foregroundStyle(task.category.color)
                    .frame(width: 24)

                Text(task.name)
                    .lineLimit(1)

                Spacer()

                Text("\(task.entries.count) \(task.entries.count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if archived {
                Button {
                    task.isArchived = false
                } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    task.isArchived = true
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
        }
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showArchived.toggle() }
            } label: {
                HStack {
                    Label("Archived", systemImage: "archivebox")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showArchived ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if showArchived {
                VStack(spacing: 0) {
                    ForEach(archivedTasks) { task in
                        taskRow(task: task, archived: true)

                        if task.id != archivedTasks.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct EditTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    let task: TrackedTask

    @State private var name: String
    @State private var category: TaskCategory
    @State private var isArchived: Bool

    init(task: TrackedTask) {
        self.task = task
        _name = State(initialValue: task.name)
        _category = State(initialValue: task.category)
        _isArchived = State(initialValue: task.isArchived)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task Name", text: $name)

                    Picker("Category", selection: $category) {
                        ForEach(TaskCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                }

                Section {
                    Toggle("Archived", isOn: $isArchived)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        task.name = name
                        task.category = category
                        task.isArchived = isArchived
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 250)
    }
}

#Preview {
    TasksView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self], inMemory: true)
}
