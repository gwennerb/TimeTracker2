//
//  CategoriesSection.swift
//  TimeTracker2
//

import SwiftUI
import SwiftData

enum CategoryOrdering {
    /// Normalise the `order` field of the supplied list to a contiguous 0..<n.
    /// Pass the list in the order you want it to appear; we'll write the
    /// indices back to each category's `order`.
    static func normaliseOrder(of categories: [Category]) {
        for (index, category) in categories.enumerated() where category.order != index {
            category.order = index
        }
    }
}

struct CategoriesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var activeCategories: [Category]
    @Query(filter: #Predicate<Category> { $0.isArchived },
           sort: [SortDescriptor(\Category.order)])
    private var archivedCategories: [Category]

    @State private var sheetMode: CategoryEditSheet.Mode?
    @State private var showArchivedDisclosure: Bool = false
    @State private var unarchiveConflict: Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.headline)

            // Use `List` so `.onMove` actually fires on macOS — `ForEach` in a
            // `VStack` silently drops the modifier. Internal scrolling is
            // disabled and the height pinned to content so the surrounding
            // `ScrollView` remains the single scroll surface.
            List {
                ForEach(activeCategories) { category in
                    activeRow(category)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.visible)
                        .listRowBackground(Color.clear)
                }
                .onMove(perform: moveCategories)

                Button {
                    sheetMode = .add
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add category")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(minHeight: CGFloat(activeCategories.count + 1) * 36)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            if !archivedCategories.isEmpty {
                DisclosureGroup(isExpanded: $showArchivedDisclosure) {
                    VStack(spacing: 0) {
                        ForEach(archivedCategories) { category in
                            archivedRow(category)
                            if category.persistentModelID != archivedCategories.last?.persistentModelID {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 4)
                } label: {
                    Text("Show archived (\(archivedCategories.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(item: $sheetMode) { mode in
            CategoryEditSheet(mode: mode)
        }
        .alert("Name conflicts with an active category",
               isPresented: Binding(
                get: { unarchiveConflict != nil },
                set: { if !$0 { unarchiveConflict = nil } }
               )) {
            Button("Edit name", role: .none) {
                if let c = unarchiveConflict {
                    sheetMode = .edit(c)
                    unarchiveConflict = nil
                }
            }
            Button("Cancel", role: .cancel) { unarchiveConflict = nil }
        } message: {
            Text("Rename this category before unarchiving so it doesn't collide with an existing active category.")
        }
    }

    private func activeRow(_ category: Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Image(systemName: category.iconSymbol)
                .foregroundStyle(category.color)
                .frame(width: 24)

            Text(category.name)
                .font(.body)

            Spacer()

            Circle()
                .fill(category.color)
                .frame(width: 12, height: 12)

            Menu {
                Button {
                    sheetMode = .edit(category)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    archive(category)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func archivedRow(_ category: Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.iconSymbol)
                .foregroundStyle(category.color)
                .frame(width: 24)

            Text(category.name)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                attemptUnarchive(category)
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(0.7)
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var working = activeCategories
        working.move(fromOffsets: source, toOffset: destination)
        CategoryOrdering.normaliseOrder(of: working)
        try? modelContext.save()
    }

    private func archive(_ category: Category) {
        category.isArchived = true
        // Compact the active order range so a later add picks up a contiguous index.
        let remaining = activeCategories.filter {
            $0.persistentModelID != category.persistentModelID
        }
        CategoryOrdering.normaliseOrder(of: remaining)
        try? modelContext.save()
    }

    private func attemptUnarchive(_ category: Category) {
        let lowered = category.name.lowercased()
        let conflict = activeCategories.contains { $0.name.lowercased() == lowered }
        if conflict {
            unarchiveConflict = category
            return
        }
        category.isArchived = false
        // Append to the end of the active order.
        let nextOrder = (activeCategories.map(\.order).max() ?? -1) + 1
        category.order = nextOrder
        try? modelContext.save()
    }
}

extension CategoryEditSheet.Mode: Identifiable {
    public var id: String {
        switch self {
        case .add: return "add"
        case .edit(let category): return "edit-\(category.persistentModelID.hashValue)"
        }
    }
}
