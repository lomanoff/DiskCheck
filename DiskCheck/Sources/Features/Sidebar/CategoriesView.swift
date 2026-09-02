import SwiftUI

struct CategoriesView: View {
    let categoryIndex: CategoryIndex
    var trashedPaths: Set<String>
    var onStage: (DiskNode) -> Void
    var onShowInTree: (DiskNode) -> Void

    @State private var selectedCategory: DiskCategory?

    private var visibleCategories: [DiskCategory] {
        categoryIndex.visibleCategories(trashedPaths: trashedPaths)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if visibleCategories.isEmpty {
                emptyState
            } else if let selectedCategory {
                categoryDetail(selectedCategory)
            } else {
                categoryList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let category = selectedCategory {
                Button(action: { selectedCategory = nil }) {
                    Label("Назад", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)

                Text(category.title)
                    .font(.title3.weight(.semibold))
                    .padding(.top, 2)

                Text(category.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Категории")
                    .font(.title3.weight(.semibold))

                let total = visibleCategories.reduce(Int64(0)) { sum, category in
                    sum + categoryIndex.totalSize(for: category, trashedPaths: trashedPaths)
                }
                Text("\(visibleCategories.count) категорий · \(ByteFormatter.format(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var categoryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(visibleCategories) { category in
                    CategoryCard(
                        category: category,
                        itemCount: categoryIndex.items(for: category).count,
                        totalSize: categoryIndex.totalSize(for: category, trashedPaths: trashedPaths)
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(16)
        }
    }

    private func categoryDetail(_ category: DiskCategory) -> some View {
        let items = categoryIndex.visibleItems(for: category, trashedPaths: trashedPaths)
        let totalSize = items.reduce(Int64(0)) { $0 + $1.node.size }

        return VStack(spacing: 0) {
            HStack {
                Image(systemName: category.systemImage)
                    .foregroundStyle(categoryTint(category))
                Text("\(items.count) объектов · \(ByteFormatter.format(totalSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        CategoryItemRow(
                            item: item,
                            displaySize: item.node.size,
                            canStage: DiskNodeDeletability.canStageForDeletion(item.node),
                            onStage: { onStage(item.node) },
                            onShowInTree: { onShowInTree(item.node) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Ничего не найдено")
                .font(.headline)
            Text("После сканирования здесь появятся git-репозитории, iCloud .nosync, кэши, node_modules и другие типовые объекты.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categoryTint(_ category: DiskCategory) -> Color {
        switch category.tintName {
        case "orange": .orange
        case "green": .green
        case "blue": .blue
        case "purple": .purple
        case "teal": .teal
        case "cyan": .cyan
        case "indigo": .indigo
        default: .secondary
        }
    }
}

private struct CategoryCard: View {
    let category: DiskCategory
    let itemCount: Int
    let totalSize: Int64
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(itemCount) · \(ByteFormatter.format(totalSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var tint: Color {
        switch category.tintName {
        case "orange": .orange
        case "green": .green
        case "blue": .blue
        case "purple": .purple
        case "teal": .teal
        case "cyan": .cyan
        case "indigo": .indigo
        default: .secondary
        }
    }
}

private struct CategoryItemRow: View {
    let item: CategorizedItem
    let displaySize: Int64
    let canStage: Bool
    var onStage: () -> Void
    var onShowInTree: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.category.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.node.name)
                    .font(.body)
                    .lineLimit(1)
                Text(shortPath(item.node.url.path))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormatter.format(displaySize))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Показать в Finder", systemImage: "folder") {
                FinderReveal.show(item.node)
            }
            if canStage {
                Button("В корзину", systemImage: "trash") {
                    onStage()
                }
            }
            Button("Показать в дереве", systemImage: "list.bullet.indent") {
                onShowInTree()
            }
        }
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
