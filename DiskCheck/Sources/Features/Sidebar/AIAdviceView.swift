import SwiftUI

struct AIAdviceView: View {
    let advice: AIDeletionAdvice?
    let state: AIAdviceState
    let extendedAdvice: AIDeletionAdvice?
    let extendedState: AIAdviceState
    let canRequestExtended: Bool
    let backendName: String?
    var trashedPaths: Set<String>
    var onRefresh: () -> Void
    var onRequestExtended: () -> Void
    var onRefreshExtended: () -> Void
    var onStage: (DiskNode) -> Void
    var onShowInTree: (DiskNode) -> Void

    @State private var selectedCategory: AISuggestedCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            switch state {
            case .loading:
                loadingState
            case .unavailable(let message):
                unavailableState(message)
            case .failed(let message):
                failedState(message)
            case .idle, .ready:
                if let selectedCategory {
                    categoryDetail(selectedCategory)
                } else if hasAnyAdvice {
                    adviceList
                } else if extendedState == .loading {
                    extendedLoadingState
                } else {
                    emptyState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if selectedCategory != nil {
                    Button { selectedCategory = nil } label: {
                        Label("Назад", systemImage: "chevron.left")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("ИИ советы", systemImage: "sparkles")
                        .font(.title3.weight(.semibold))
                }

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Обновить рекомендации")
                .disabled(state == .loading)
            }

            if let category = selectedCategory {
                Text(category.title)
                    .font(.title3.weight(.semibold))
                    .padding(.top, 2)

                Text(category.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let advice {
                Text(providerSubtitle(advice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func providerSubtitle(_ advice: AIDeletionAdvice) -> String {
        let provider = backendName ?? advice.providerName
        return "\(provider) · \(advice.categories.count) категорий · \(ByteFormatter.format(advice.totalReclaimableSize))"
    }

    private var hasAnyAdvice: Bool {
        !(advice?.categories.isEmpty ?? true) || !(extendedAdvice?.categories.isEmpty ?? true)
    }

    private var adviceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let advice, !advice.categories.isEmpty {
                    adviceSection(
                        title: AIAdviceScope.overview.sectionTitle,
                        subtitle: "Топ папок и типовые объекты",
                        categories: advice.categories
                    )
                }

                extendedSection
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var extendedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AIAdviceScope.remainingFiles.sectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("До 400 дополнительных путей вне основного обзора")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            switch extendedState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Анализ остальных файлов…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

            case .ready:
                if let extendedAdvice, !extendedAdvice.categories.isEmpty {
                    ForEach(extendedAdvice.categories) { category in
                        AIAdviceCategoryCard(category: category) {
                            selectedCategory = category
                        }
                    }
                }

            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if canRequestExtended {
                    Button("Повторить", action: onRefreshExtended)
                        .controlSize(.small)
                }

            case .unavailable(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .idle:
                if canRequestExtended {
                    Button {
                        onRequestExtended()
                    } label: {
                        Label("Спросить ИИ об остальных файлах", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
    }

    private func adviceSection(
        title: String,
        subtitle: String,
        categories: [AISuggestedCategory]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            ForEach(categories) { category in
                AIAdviceCategoryCard(category: category) {
                    selectedCategory = category
                }
            }
        }
    }

    private var extendedLoadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("ИИ анализирует остальные файлы…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categoryDetail(_ category: AISuggestedCategory) -> some View {
        let items = category.items.filter { item in
            !DiskNodeTrash.isTrashed(item.node, trashedPaths: trashedPaths)
        }

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: category.safety.systemImage)
                    .foregroundStyle(safetyTint(category.safety))
                Text("\(category.safety.title) · \(items.count) · \(ByteFormatter.format(items.reduce(0) { $0 + $1.node.size }))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        AIAdviceItemRow(
                            item: item,
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

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("ИИ анализирует дерево файлов…")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let backendName {
                Text(backendName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("ИИ недоступна")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let advice, !advice.categories.isEmpty {
                Text("Показаны рекомендации по встроенным правилам.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Не удалось получить совет ИИ")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Повторить", action: onRefresh)
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Нет рекомендаций")
                .font(.headline)
            Text("После сканирования ИИ предложит категории для очистки, если доступна Apple Intelligence или Ollama.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func safetyTint(_ safety: DeletionSafety) -> Color {
        switch safety {
        case .safe: .green
        case .caution: .orange
        case .dangerous: .red
        }
    }
}

private struct AIAdviceCategoryCard: View {
    let category: AISuggestedCategory
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: category.safety.systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(category.items.count) · \(ByteFormatter.format(category.totalSize))")
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
        switch category.safety {
        case .safe: .green
        case .caution: .orange
        case .dangerous: .red
        }
    }
}

private struct AIAdviceItemRow: View {
    let item: AISuggestedItem
    let canStage: Bool
    var onStage: () -> Void
    var onShowInTree: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.node.isDirectory ? "folder.fill" : "doc.fill")
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

            Text(ByteFormatter.format(item.node.size))
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
                Button("В корзину", systemImage: "trash", action: onStage)
            }
            Button("Показать в дереве", systemImage: "list.bullet.indent", action: onShowInTree)
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
