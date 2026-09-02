import SwiftUI

struct LegendView: View {
    let node: DiskNode
    let breadcrumbItems: [DiskNode]
    let canGoBack: Bool
    let totalCapacity: Int64
    let availableSpace: Int64
    let rootScannedSize: Int64
    let isAtScanRoot: Bool
    var trashedPaths: Set<String>
    var expandingLazyScanPath: String?
    var onBack: () -> Void
    var onNavigateTo: (Int) -> Void
    var onSelect: (DiskNode) -> Void
    var onStage: (DiskNode) -> Void

    private var displayNode: DiskNode {
        DiskNodeTrash.filteredForLegend(node, trashedPaths: trashedPaths)
    }

    private var groupedChildren: (deletable: [DiskNode], protected: [DiskNode]) {
        DiskNodeDeletability.groupedChildren(displayNode.children)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                TreeNavigationHeader(
                    items: breadcrumbItems,
                    canGoBack: canGoBack,
                    onBack: onBack,
                    onSelect: onNavigateTo
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name)
                        .font(.title3.weight(.semibold))
                    Text(ByteFormatter.format(displayNode.size))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.secondary)

                    if expandingLazyScanPath == node.url.standardizedFileURL.path {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Раскрываем содержимое…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let groups = groupedChildren

                    if !groups.deletable.isEmpty {
                        LegendSectionHeader(
                            title: "Можно удалить",
                            count: groups.deletable.count,
                            totalSize: groups.deletable.reduce(0) { $0 + $1.size },
                            systemImage: "trash",
                            tint: .orange
                        )

                        ForEach(groups.deletable) { child in
                            LegendRow(
                                node: child,
                                canStage: DiskNodeDeletability.canStageForDeletion(child),
                                onTap: { onSelect(child) },
                                onStage: { onStage(child) }
                            )
                        }
                    }

                    if !groups.protected.isEmpty {
                        if !groups.deletable.isEmpty {
                            Spacer().frame(height: 8)
                        }

                        LegendSectionHeader(
                            title: "Защищено системой",
                            count: groups.protected.count,
                            totalSize: groups.protected.reduce(0) { $0 + $1.size },
                            systemImage: "lock.fill",
                            tint: .secondary
                        )

                        ForEach(groups.protected) { child in
                            LegendRow(
                                node: child,
                                canStage: false,
                                onTap: { onSelect(child) },
                                onStage: { onStage(child) }
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if availableSpace > 0 {
                    HStack {
                        Circle()
                            .fill(Color(white: 0.25))
                            .frame(width: 10, height: 10)
                        Text("Свободное пространство")
                            .font(.subheadline)
                        Spacer()
                        Text(ByteFormatter.format(availableSpace))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if isAtScanRoot, totalCapacity > 0 {
                    let used = totalCapacity - availableSpace
                    let hidden = max(0, used - rootScannedSize)
                    if hidden > 0 {
                        HStack(alignment: .top) {
                            Circle()
                                .fill(Color(white: 0.18))
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Не просканировано на диске")
                                    .font(.subheadline)
                                Text("Разница между занятым местом тома и результатом сканирования. Часто это системные папки без Full Disk Access.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(ByteFormatter.format(hidden))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct LegendSectionHeader: View {
    let title: String
    let count: Int
    let totalSize: Int64
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Spacer()

            Text("\(count) · \(ByteFormatter.format(totalSize))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

private struct LegendRow: View {
    let node: DiskNode
    let canStage: Bool
    var onTap: () -> Void
    var onStage: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ColorPalette.color(for: node))
                .frame(width: 10, height: 10)

            Text(node.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            if node.needsLazyScan {
                Image(systemName: "arrow.down.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(ByteFormatter.format(node.size))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory, !node.children.isEmpty || node.needsLazyScan {
                onTap()
            }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Показать в Finder", systemImage: "folder") {
                FinderReveal.show(node)
            }
            if canStage {
                Button("В корзину", systemImage: "trash") {
                    onStage()
                }
            }
        }
    }
}
