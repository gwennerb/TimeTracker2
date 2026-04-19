//
//  QuickEntryView.swift
//  TimeTracker2
//

import SwiftUI
import SwiftData

struct QuickEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [TimeEntry]
    @Query private var allTasks: [TrackedTask]
    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var viewModel = QuickEntryViewModel()
    @State private var showingNewTaskSheet = false
    @State private var dayForDetailSheet: Date?
    @State private var showingDaySheet = false

    private var activeProjects: [Project] {
        allProjects.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(spacing: 16) {
            weekHeader
            projectPicker

            if viewModel.selectedProject == nil {
                emptyProjectState
            } else {
                gridScroll
                footer
            }
        }
        .padding()
        .onAppear { ensureProjectSelection() }
        .onChange(of: allProjects) { _, _ in ensureProjectSelection() }
        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskSheet { _ in }
        }
        .sheet(isPresented: $showingDaySheet) {
            if let date = dayForDetailSheet {
                TimeEntrySheet(date: date, tasks: allTasks)
            }
        }
    }

    private var weekHeader: some View {
        HStack {
            Button(action: viewModel.previousWeek) {
                Image(systemName: "chevron.left").font(.title2)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.weekRangeString)
                    .font(.title3)
                    .fontWeight(.semibold)
                Button("Today") { viewModel.goToCurrentWeek() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: viewModel.nextWeek) {
                Image(systemName: "chevron.right").font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var projectPicker: some View {
        Picker("Project", selection: $viewModel.selectedProject) {
            ForEach(activeProjects) { project in
                Text(project.name).tag(project as Project?)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(activeProjects.isEmpty)
    }

    private var emptyProjectState: some View {
        ContentUnavailableView {
            Label("Pick a Project", systemImage: "folder")
        } description: {
            Text(activeProjects.isEmpty
                 ? "Create a project from the Projects tab to start logging time."
                 : "Select a project above to load its weekly grid.")
        }
        .frame(maxHeight: .infinity)
    }

    private var taskRows: [TrackedTask] {
        viewModel.taskRows(allTasks: allTasks, entries: entries)
    }

    private var gridScroll: some View {
        ScrollView([.vertical]) {
            VStack(spacing: 0) {
                gridHeaderRow
                Divider()
                ForEach(taskRows) { task in
                    QuickEntryRow(
                        task: task,
                        viewModel: viewModel,
                        entries: entries,
                        modelContext: modelContext,
                        onMultiCellTap: openDaySheet
                    )
                    Divider().padding(.leading, 12)
                }
                addTaskRow
                Divider()
                gridTotalRow
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var gridHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Task")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .leading)
                .padding(.leading, 12)

            ForEach(viewModel.weekDates, id: \.self) { date in
                VStack(spacing: 2) {
                    Text(viewModel.dayLabel(for: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.dayNumber(for: date))
                        .font(.caption)
                        .fontWeight(viewModel.isToday(date) ? .bold : .medium)
                        .foregroundStyle(viewModel.isToday(date) ? Color.accentColor : .primary)
                }
                .frame(maxWidth: .infinity)
            }

            Text("Total")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
    }

    private var gridTotalRow: some View {
        HStack(spacing: 0) {
            Text("Total")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(width: 200, alignment: .leading)
                .padding(.leading, 12)

            ForEach(viewModel.weekDates, id: \.self) { date in
                Text(formatHours(viewModel.columnTotal(date: date, entries: entries)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            Text(formatHours(viewModel.weekTotal(entries: entries)))
                .font(.subheadline)
                .fontWeight(.bold)
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .padding(.vertical, 10)
    }

    private var addTaskRow: some View {
        Button {
            showingNewTaskSheet = true
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                Text("Add Task")
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Button {
                _ = EntryDuplicator.duplicateWeek(
                    from: viewModel.previousWeekStart(),
                    to: viewModel.weekStart,
                    among: entries.filter { $0.project?.id == viewModel.selectedProject?.id },
                    in: modelContext
                )
            } label: {
                Label("Repeat Last Week", systemImage: "arrow.clockwise")
            }
            .help("Copy last week's entries into empty cells of this week")

            Spacer()
        }
    }

    private func openDaySheet(_ date: Date) {
        dayForDetailSheet = date
        showingDaySheet = true
    }

    private func ensureProjectSelection() {
        if let selected = viewModel.selectedProject,
           activeProjects.contains(where: { $0.id == selected.id }) {
            return
        }
        viewModel.selectedProject = activeProjects.first
    }

    private func formatHours(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f", value) : "—"
    }
}

private struct QuickEntryRow: View {
    let task: TrackedTask
    let viewModel: QuickEntryViewModel
    let entries: [TimeEntry]
    let modelContext: ModelContext
    let onMultiCellTap: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: task.category.icon)
                    .foregroundStyle(task.category.color)
                Text(task.name)
                    .font(.body)
                    .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)
            .padding(.leading, 12)

            ForEach(viewModel.weekDates, id: \.self) { date in
                QuickEntryCell(
                    state: viewModel.cellState(task: task, date: date, entries: entries),
                    onCommit: { newValue in
                        let state = viewModel.cellState(task: task, date: date, entries: entries)
                        viewModel.commitCell(
                            task: task,
                            date: date,
                            newValue: newValue,
                            currentState: state,
                            in: modelContext
                        )
                    },
                    onTapMulti: { onMultiCellTap(date) }
                )
                .frame(maxWidth: .infinity)
            }

            Text(rowTotalString)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .padding(.vertical, 4)
    }

    private var rowTotalString: String {
        let total = viewModel.rowTotal(task: task, entries: entries)
        return total > 0 ? String(format: "%.1f", total) : "—"
    }
}

private struct QuickEntryCell: View {
    let state: QuickEntryCellState
    let onCommit: (Double?) -> Void
    let onTapMulti: () -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            switch state {
            case .multi(let count, let total):
                Button(action: onTapMulti) {
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", total))
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text("\(count)×")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Multiple entries — open day to edit")
            default:
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                    .onChange(of: isFocused) { wasFocused, nowFocused in
                        if wasFocused && !nowFocused {
                            commit()
                        }
                    }
                    .onSubmit { commit() }
            }
        }
        .padding(.horizontal, 4)
        .onAppear { syncText() }
        .onChange(of: state) { _, _ in if !isFocused { syncText() } }
    }

    private func syncText() {
        switch state {
        case .empty: text = ""
        case .single(let entry): text = formatHours(entry.duration)
        case .multi: text = ""
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty {
            onCommit(0)
            syncText()
            return
        }
        guard let value = Double(trimmed), value >= 0 else {
            syncText()
            return
        }
        onCommit(value)
        syncText()
    }

    private func formatHours(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2g", value)
    }
}

#Preview {
    QuickEntryView()
        .modelContainer(for: [TrackedTask.self, TimeEntry.self, Project.self, DayOff.self], inMemory: true)
}
