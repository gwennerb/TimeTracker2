//
//  TasksView.swift
//  TimeTracker2
//

import SwiftUI
import SwiftData

struct TasksView: View {
    @Query(sort: \TrackedTask.name) private var allTasks: [TrackedTask]
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]
    @Query(filter: #Predicate<Category> { $0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var archivedCategories: [Category]

    @State private var showArchivedTasks: Bool = false
    @State private var showArchivedCategories: Bool = false
    @State private var editingTask: TrackedTask?

    private var activeTasks: [TrackedTask] {
        allTasks.filter { !$0.isArchived }
    }

    private var archivedTasks: [TrackedTask] {
        allTasks.filter { $0.isArchived }
    }

    private func tasks(for category: Category, includeArchivedTasks: Bool) -> [TrackedTask] {
        let pool = includeArchivedTasks ? allTasks : activeTasks
        return pool
            .filter { $0.category?.persistentModelID == category.persistentModelID }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                viewHeader

                ForEach(activeCategories) { category in
                    let categoryTasks = tasks(for: category, includeArchivedTasks: false)
                    if !categoryTasks.isEmpty {
                        categorySection(category: category,
                                        tasks: categoryTasks,
                                        archivedCategory: false)
                    }
                }

                if activeTasks.isEmpty && !showArchivedTasks {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "tray")
                    } description: {
                        Text("Tasks created when logging time will appear here.")
                    }
                }

                if showArchivedCategories {
                    ForEach(archivedCategories) { category in
                        let categoryTasks = tasks(for: category, includeArchivedTasks: true)
                        if !categoryTasks.isEmpty {
                            categorySection(category: category,
                                            tasks: categoryTasks,
                                            archivedCategory: true)
                        }
                    }
                }

                if !archivedTasks.isEmpty {
                    archivedTasksSection
                }
            }
            .padding()
        }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task)
        }
    }

    private var viewHeader: some View {
        HStack {
            Text("Tasks")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Toggle("Show archived categories", isOn: $showArchivedCategories)
                .toggleStyle(.switch)
                .help("Reveals categories that have been archived so historical tasks stay reachable.")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func categorySection(category: Category,
                                 tasks: [TrackedTask],
                                 archivedCategory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(category.name, systemImage: category.iconSymbol)
                    .font(.headline)
                    .foregroundStyle(category.color)
                if archivedCategory {
                    Text("Archived")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    taskRow(task: task, archivedCategory: archivedCategory)

                    if task.id != tasks.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .opacity(archivedCategory ? 0.55 : 1.0)
    }

    private func taskRow(task: TrackedTask, archivedCategory: Bool) -> some View {
        Button {
            editingTask = task
        } label: {
            HStack {
                Image(systemName: task.category?.iconSymbol ?? "questionmark.circle")
                    .foregroundStyle(task.category?.color ?? .gray)
                    .frame(width: 24)

                Text(task.name)
                    .lineLimit(1)

                if task.isArchived {
                    Text("Archived task")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }

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
            if task.isArchived {
                Button {
                    task.isArchived = false
                } label: {
                    Label("Unarchive task", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    task.isArchived = true
                } label: {
                    Label("Archive task", systemImage: "archivebox")
                }
            }
        }
    }

    private var archivedTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showArchivedTasks.toggle() }
            } label: {
                HStack {
                    Label("Archived tasks", systemImage: "archivebox")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showArchivedTasks ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if showArchivedTasks {
                VStack(spacing: 0) {
                    ForEach(archivedTasks) { task in
                        taskRow(task: task, archivedCategory: false)

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

    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]

    let task: TrackedTask

    @State private var name: String
    @State private var selectedCategory: Category?
    @State private var isArchived: Bool

    init(task: TrackedTask) {
        self.task = task
        _name = State(initialValue: task.name)
        _selectedCategory = State(initialValue: task.category)
        _isArchived = State(initialValue: task.isArchived)
    }

    private var pickerCategories: [Category] {
        // Always include the currently selected category, even if it has been archived,
        // so the picker doesn't silently drop the assignment.
        var list = activeCategories
        if let current = selectedCategory,
           !list.contains(where: { $0.persistentModelID == current.persistentModelID }) {
            list.insert(current, at: 0)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task Name", text: $name)

                    Picker("Category", selection: $selectedCategory) {
                        Text("Select a category…").tag(nil as Category?)
                        ForEach(pickerCategories) { category in
                            Label(category.name, systemImage: category.iconSymbol)
                                .tag(category as Category?)
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
                        task.category = selectedCategory
                        task.isArchived = isArchived
                        dismiss()
                    }
                    .disabled(name.isEmpty || selectedCategory == nil)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 250)
    }
}

#Preview {
    TasksView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self, Category.self], inMemory: true)
}
