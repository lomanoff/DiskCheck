import AppKit
import SwiftUI

struct TrashBinView: View {
    @Bindable var trashStore: TrashStore
    var onEmptyComplete: () async -> Void

    @State private var showEmptyChoice = false
    @State private var isExpanded = false

    private let rowHeight: CGFloat = 30

    private var listMaxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) * 0.5
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded, !trashStore.items.isEmpty {
                itemList
                Divider().opacity(0.35)
            }

            header
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .overlay {
            if let countdown = trashStore.emptyCountdown, countdown > 0,
               let operation = trashStore.pendingOperation {
                TrashCountdownOverlay(
                    countdown: countdown,
                    operation: operation,
                    itemCount: trashStore.itemCount,
                    totalSize: trashStore.totalSize,
                    onCancel: { trashStore.cancelEmptyCountdown() }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .confirmationDialog(
            "Как очистить корзину?",
            isPresented: $showEmptyChoice,
            titleVisibility: .visible
        ) {
            Button("В системную корзину") {
                trashStore.startEmptyCountdown(operation: .moveToSystemTrash) {
                    await onEmptyComplete()
                }
            }
            Button("Удалить навсегда", role: .destructive) {
                trashStore.startEmptyCountdown(operation: .permanentDelete) {
                    await onEmptyComplete()
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("\(trashStore.itemCount) объектов (\(ByteFormatter.format(trashStore.totalSize))). Выберите способ удаления — через 10 секунд можно отменить.")
        }
        .onChange(of: trashStore.itemCount) { _, count in
            if count == 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded = false
                }
            }
        }
    }

    private var borderColor: Color {
        trashStore.itemCount > 0 ? Color.red.opacity(0.25) : Color.primary.opacity(0.08)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                guard trashStore.itemCount > 0 else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(trashStore.itemCount > 0 ? Color.red.opacity(0.14) : Color.primary.opacity(0.06))
                        .frame(width: 36, height: 36)

                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(trashStore.itemCount > 0 ? .red : .secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(trashStore.itemCount == 0)
            .help(trashStore.itemCount > 0 ? (isExpanded ? "Свернуть список" : "Показать список") : "")

            VStack(alignment: .leading, spacing: 2) {
                Text("Корзина")
                    .font(.subheadline.weight(.semibold))

                if trashStore.itemCount > 0 {
                    Text("\(trashStore.itemCount) объектов · \(ByteFormatter.format(trashStore.totalSize))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Помеченные файлы появятся здесь")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if trashStore.itemCount > 0, trashStore.emptyCountdown == nil {
                Button("Очистить…") {
                    showEmptyChoice = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var listContentHeight: CGFloat {
        CGFloat(trashStore.itemCount) * rowHeight
    }

    private var itemList: some View {
        Group {
            if listContentHeight <= listMaxHeight {
                itemRows
            } else {
                ScrollView {
                    itemRows
                }
                .frame(height: listMaxHeight)
            }
        }
        .padding(.bottom, 4)
    }

    private var itemRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(trashStore.items) { item in
                TrashItemRow(item: item, rowHeight: rowHeight) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        trashStore.restore(item)
                    }
                }
            }
        }
    }
}

private struct TrashItemRow: View {
    let item: TrashItem
    let rowHeight: CGFloat
    var onRestore: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(ByteFormatter.format(item.size))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            if isHovered {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Вернуть")
            }
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 14)
        .background(isHovered ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Вернуть", systemImage: "arrow.uturn.backward") {
                onRestore()
            }
        }
    }
}

private struct TrashCountdownOverlay: View {
    let countdown: Int
    let operation: TrashEmptyOperation
    let itemCount: Int
    let totalSize: Int64
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThickMaterial)

            HStack(spacing: 16) {
                Text("\(countdown)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(operation == .permanentDelete ? .red : .orange)
                    .contentTransition(.numericText())
                    .frame(width: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(operationTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Отменить") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var operationTitle: String {
        switch operation {
        case .moveToSystemTrash:
            "Перемещение \(itemCount) объектов (\(ByteFormatter.format(totalSize))) в системную корзину"
        case .permanentDelete:
            "Удаление \(itemCount) объектов (\(ByteFormatter.format(totalSize))) навсегда"
        }
    }
}
