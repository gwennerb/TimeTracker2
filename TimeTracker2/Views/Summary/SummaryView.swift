//
//  SummaryView.swift
//  TimeTracker2
//
//  Created by Per Bergström on 2025-12-06.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct SummaryView: View {
    @Query private var entries: [TimeEntry]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query private var daysOff: [DayOff]
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]
    @Query(filter: #Predicate<Category> { $0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var archivedCategories: [Category]

    @State private var viewModel = SummaryViewModel()
    @State private var expandedCategories: Set<PersistentIdentifier> = []
    @State private var hasSeededExpansion: Bool = false
    @State private var showArchivedCategories: Bool = false
    @State private var exportStatusMessage: String?
    @State private var isExporting = false
    @State private var exportDocument = SummaryTextDocument(text: "")

    private var projectsForPicker: [Project] {
        viewModel.projectsWithEntriesInMonth(entries)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthHeader

                if !projectsForPicker.isEmpty {
                    projectPicker
                }

                if viewModel.selectedProject == nil && !projectsForPicker.isEmpty {
                    projectTotalsStrip
                }

                totalHoursCard

                categoryCards
            }
            .padding()
        }
        .onChange(of: viewModel.selectedMonth) { _, _ in
            pruneSelectionIfMissing()
        }
        .onChange(of: allProjects) { _, _ in
            pruneSelectionIfMissing()
        }
        .onChange(of: activeCategories) { _, newValue in
            seedExpansionIfNeeded(active: newValue)
        }
        .task { seedExpansionIfNeeded(active: activeCategories) }
        .alert("Summary Export", isPresented: Binding(
            get: { exportStatusMessage != nil },
            set: { if !$0 { exportStatusMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportStatusMessage ?? "")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: defaultExportFileName
        ) { result in
            switch result {
            case .success(let url):
                exportStatusMessage = "Summary exported to \(url.lastPathComponent)."
            case .failure(let error):
                if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
                    return
                }
                exportStatusMessage = "Export failed: \(error.localizedDescription)"
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

            Toggle("Archived", isOn: $showArchivedCategories)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Surface archived categories so historical hours stay reachable.")

            Button(action: copyForDiscord) {
                Label("Copy for Discord", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.plain)

            Button(action: exportSummary) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var projectPicker: some View {
        Picker("Project", selection: $viewModel.selectedProject) {
            Text("All").tag(nil as Project?)
            ForEach(projectsForPicker) { project in
                Text(project.name).tag(project as Project?)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var projectTotalsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project Totals")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(projectsForPicker) { project in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(project.name)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1fh", viewModel.totalHoursForProject(project, entries: entries)))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if project.id != projectsForPicker.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var totalHoursCard: some View {
        VStack(spacing: 8) {
            Text(totalHoursLabel)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(String(format: "%.1f", viewModel.totalHoursForMonth(entries)))
                .font(.system(size: 48, weight: .bold, design: .rounded))

            if viewModel.selectedProject == nil {
                expectedHoursLine
                let dayOffHours = viewModel.dayOffHoursForMonth(daysOff)
                if dayOffHours > 0 {
                    Text(String(format: "Day off: %.1fh", dayOffHours))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(totalHoursSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var expectedHoursLine: some View {
        let expected = viewModel.expectedHoursForMonth(daysOff)
        let total = viewModel.totalHoursForMonth(entries)
        let delta = total - expected
        let sign = delta >= 0 ? "+" : "−"
        let deltaText = String(format: "%@%.1fh", sign, abs(delta))
        let deltaColor: Color = delta >= 0 ? .green : .orange
        return HStack(spacing: 6) {
            Text(String(format: "Expected: %.1fh", expected))
                .foregroundStyle(.secondary)
            Text("(\(deltaText))")
                .foregroundStyle(deltaColor)
        }
        .font(.subheadline)
    }

    private var totalHoursLabel: String {
        if let project = viewModel.selectedProject {
            return "\(project.name) Hours"
        }
        return "Total Hours"
    }

    private var totalHoursSubtitle: String {
        if viewModel.selectedProject != nil {
            return "hours logged for this project"
        }
        return "hours logged this month"
    }

    private var categoryCards: some View {
        VStack(spacing: 12) {
            ForEach(activeCategories) { category in
                let categoryHours = viewModel.totalHoursForCategory(category, entries: entries)
                if categoryHours > 0 {
                    CategoryCard(
                        category: category,
                        totalHours: categoryHours,
                        taskHours: viewModel.taskHoursForCategory(category, entries: entries),
                        isExpanded: expandedCategories.contains(category.persistentModelID),
                        archived: false
                    ) {
                        toggleCategory(category.persistentModelID)
                    }
                }
            }

            if showArchivedCategories {
                ForEach(archivedCategories) { category in
                    let categoryHours = viewModel.totalHoursForCategory(category, entries: entries)
                    if categoryHours > 0 {
                        CategoryCard(
                            category: category,
                            totalHours: categoryHours,
                            taskHours: viewModel.taskHoursForCategory(category, entries: entries),
                            isExpanded: expandedCategories.contains(category.persistentModelID),
                            archived: true
                        ) {
                            toggleCategory(category.persistentModelID)
                        }
                    }
                }
            }
        }
    }

    private func toggleCategory(_ id: PersistentIdentifier) {
        withAnimation {
            if expandedCategories.contains(id) {
                expandedCategories.remove(id)
            } else {
                expandedCategories.insert(id)
            }
        }
    }

    private func seedExpansionIfNeeded(active: [Category]) {
        guard !hasSeededExpansion, !active.isEmpty else { return }
        expandedCategories = Set(active.map { $0.persistentModelID })
        hasSeededExpansion = true
    }

    private func pruneSelectionIfMissing() {
        guard let selected = viewModel.selectedProject else { return }
        if !projectsForPicker.contains(where: { $0.id == selected.id }) {
            viewModel.selectedProject = nil
        }
    }

    private var allCategoriesForExport: [Category] {
        activeCategories + archivedCategories
    }

    private func exportSummary() {
        exportDocument = SummaryTextDocument(
            text: viewModel.exportText(for: entries, categories: allCategoriesForExport)
        )
        isExporting = true
    }

    private func copyForDiscord() {
        let text = viewModel.discordExportText(
            for: entries,
            expectedHours: viewModel.expectedHoursForMonth(daysOff),
            categories: allCategoriesForExport
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        exportStatusMessage = "Copied to clipboard. Paste into Discord."
    }

    private var defaultExportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let monthPart = formatter.string(from: viewModel.selectedMonth)
        if let project = viewModel.selectedProject {
            let safeName = project.name
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
            return "Summary-\(monthPart)-\(safeName).txt"
        }
        return "Summary-\(monthPart).txt"
    }
}

private struct SummaryTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct CategoryCard: View {
    let category: Category
    let totalHours: Double
    let taskHours: [(task: TrackedTask, hours: Double)]
    let isExpanded: Bool
    let archived: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: category.iconSymbol)
                        .font(.title2)
                        .foregroundStyle(category.color)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.headline)
                        if archived {
                            Text("Archived")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

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

            if isExpanded && !taskHours.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(taskHours, id: \.task.id) { item in
                        TaskHoursRow(taskName: item.task.name,
                                     hours: item.hours,
                                     color: category.color)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(archived ? 0.55 : 1.0)
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
        .modelContainer(for: [TrackedTask.self, TimeEntry.self, Project.self], inMemory: true)
}
