//
//  CategoryEditSheet.swift
//  TimeTracker2
//

import SwiftUI
import SwiftData

struct CategoryEditSheet: View {
    enum Mode {
        case add
        case edit(Category)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String
    @State private var colorName: String
    @State private var iconSymbol: String
    @State private var validationError: CategoryValidationResult = .ok

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _colorName = State(initialValue: "blue")
            _iconSymbol = State(initialValue: "app.fill")
        case .edit(let category):
            _name = State(initialValue: category.name)
            _colorName = State(initialValue: category.colorName)
            _iconSymbol = State(initialValue: category.iconSymbol)
        }
    }

    private var resolvedColor: Color {
        Category.colorPalette[colorName] ?? .gray
    }

    private var editingCategory: Category? {
        if case .edit(let c) = mode { return c }
        return nil
    }

    private var canSave: Bool {
        validationError == .ok
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    HStack(spacing: 12) {
                        Image(systemName: iconSymbol)
                            .font(.title2)
                            .foregroundStyle(resolvedColor)
                            .frame(width: 32)
                        Text(name.isEmpty ? "Category name" : name)
                            .font(.headline)
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Name") {
                    TextField("Category name", text: $name)
                        .onChange(of: name) { _, _ in revalidate() }
                    if validationError == .duplicate {
                        Text("Another active category already uses this name.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if validationError == .empty {
                        Text("Name cannot be empty.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                              spacing: 12) {
                        ForEach(Category.colorPaletteOrder, id: \.self) { key in
                            colorSwatch(key: key)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                              spacing: 8) {
                        ForEach(Category.iconPalette, id: \.self) { symbol in
                            iconSwatch(symbol: symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editingCategory == nil ? "New Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { revalidate() }
        }
        .frame(minWidth: 460, minHeight: 540)
    }

    private func colorSwatch(key: String) -> some View {
        let isSelected = key == colorName
        return Button {
            colorName = key
        } label: {
            Circle()
                .fill(Category.colorPalette[key] ?? .gray)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
        .help(key.capitalized)
    }

    private func iconSwatch(symbol: String) -> some View {
        let isSelected = symbol == iconSymbol
        return Button {
            iconSymbol = symbol
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(isSelected ? 0.8 : 0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func revalidate() {
        validationError = CategoryValidation.validate(name: name,
                                                      editing: editingCategory,
                                                      in: modelContext)
    }

    private func save() {
        let trimmed = CategoryValidation.trimmed(name)
        switch mode {
        case .add:
            let nextOrder = nextOrderValue()
            let category = Category(name: trimmed,
                                    colorName: colorName,
                                    iconSymbol: iconSymbol,
                                    order: nextOrder)
            modelContext.insert(category)
        case .edit(let category):
            category.name = trimmed
            category.colorName = colorName
            category.iconSymbol = iconSymbol
        }
        dismiss()
    }

    private func nextOrderValue() -> Int {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { !$0.isArchived }
        )
        let active = (try? modelContext.fetch(descriptor)) ?? []
        return (active.map(\.order).max() ?? -1) + 1
    }
}

#Preview {
    CategoryEditSheet(mode: .add)
        .modelContainer(for: [Category.self, TrackedTask.self, TimeEntry.self,
                              Project.self, DayOff.self], inMemory: true)
}
