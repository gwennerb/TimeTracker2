//
//  ProjectsView.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2026-04-19.
//

import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var allProjects: [Project]
    @State private var showArchived: Bool = false
    @State private var editingProject: Project?
    @State private var showingNewProjectSheet: Bool = false

    private var activeProjects: [Project] {
        allProjects.filter { !$0.isArchived }
    }

    private var archivedProjects: [Project] {
        allProjects.filter { $0.isArchived }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                createButton

                if activeProjects.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects", systemImage: "folder")
                    } description: {
                        Text("Create a project to start tagging time entries.")
                    }
                } else {
                    activeSection
                }

                if !archivedProjects.isEmpty {
                    archivedSection
                }
            }
            .padding()
        }
        .sheet(item: $editingProject) { project in
            EditProjectSheet(project: project)
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet()
        }
    }

    private var createButton: some View {
        Button {
            showingNewProjectSheet = true
        } label: {
            Label("Create New Project", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var activeSection: some View {
        VStack(spacing: 0) {
            ForEach(activeProjects) { project in
                projectRow(project: project, archived: false)

                if project.id != activeProjects.last?.id {
                    Divider().padding(.leading, 36)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func projectRow(project: Project, archived: Bool) -> some View {
        Button {
            editingProject = project
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(project.name)
                    .lineLimit(1)

                Spacer()

                Text("\(project.entries.count) \(project.entries.count == 1 ? "entry" : "entries")")
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
                    project.isArchived = false
                } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    project.isArchived = true
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }

            if project.entries.isEmpty {
                Divider()
                Button(role: .destructive) {
                    modelContext.delete(project)
                } label: {
                    Label("Delete", systemImage: "trash")
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
                    ForEach(archivedProjects) { project in
                        projectRow(project: project, archived: true)

                        if project.id != archivedProjects.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct EditProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: Project

    @State private var name: String
    @State private var isArchived: Bool
    @State private var showingDeleteConfirmation: Bool = false

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _isArchived = State(initialValue: project.isArchived)
    }

    private var canDelete: Bool { project.entries.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $name)
                }

                Section {
                    Toggle("Archived", isOn: $isArchived)
                } footer: {
                    Text("Archived projects keep their history but are hidden when logging new time.")
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Project", systemImage: "trash")
                            Spacer()
                        }
                    }
                    .disabled(!canDelete)
                } footer: {
                    if !canDelete {
                        Text("Projects with logged time can't be deleted. Archive instead to preserve history.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        project.name = name
                        project.isArchived = isArchived
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete Project", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(project)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(project.name)\"? This cannot be undone.")
            }
        }
        .frame(minWidth: 320, minHeight: 280)
    }
}

struct NewProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var onProjectCreated: (Project) -> Void = { _ in }

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $name)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let project = Project(name: trimmed)
                        modelContext.insert(project)
                        onProjectCreated(project)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 180)
    }
}

#Preview {
    ProjectsView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self, Project.self], inMemory: true)
}
