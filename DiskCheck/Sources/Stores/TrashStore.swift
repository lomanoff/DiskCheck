import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class TrashStore {
    var items: [TrashItem] = []
    var emptyCountdown: Int?
    var pendingOperation: TrashEmptyOperation?
    var isEmptying = false
    private(set) var trashedPathsRevision = 0

    private var countdownTask: Task<Void, Never>?
    private var cachedTrashedPaths: Set<String>?

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var itemCount: Int { items.count }

    var trashedPaths: Set<String> {
        if let cachedTrashedPaths { return cachedTrashedPaths }
        let paths = Set(items.map(\.path))
        cachedTrashedPaths = paths
        return paths
    }

    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return items.contains { item in
            path == item.path || path.hasPrefix(item.path + "/")
        }
    }

    func add(_ node: DiskNode) {
        let path = node.url.standardizedFileURL.path
        guard !contains(node.url) else { return }
        guard !items.contains(where: { $0.path == path }) else { return }

        items.append(TrashItem(
            url: node.url,
            name: node.name,
            size: node.size,
            isDirectory: node.isDirectory
        ))
        items.sort { $0.size > $1.size }
        invalidateTrashedPathsCache()
    }

    func remove(_ item: TrashItem) {
        items.removeAll { $0.id == item.id }
        invalidateTrashedPathsCache()
    }

    func restore(_ item: TrashItem) {
        remove(item)
    }

    func clear() {
        cancelEmptyCountdown()
        items = []
        invalidateTrashedPathsCache()
    }

    func cancelEmptyCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        emptyCountdown = nil
        pendingOperation = nil
        isEmptying = false
    }

    func startEmptyCountdown(
        operation: TrashEmptyOperation,
        onComplete: @escaping () async -> Void
    ) {
        guard !items.isEmpty else { return }

        cancelEmptyCountdown()
        isEmptying = true
        pendingOperation = operation
        emptyCountdown = 10

        countdownTask = Task {
            for remaining in stride(from: 10, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                emptyCountdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }

            guard !Task.isCancelled else { return }
            emptyCountdown = 0
            await onComplete()
            emptyCountdown = nil
            pendingOperation = nil
            isEmptying = false
        }
    }

    func execute(_ operation: TrashEmptyOperation) async -> [String] {
        guard !items.isEmpty else { return [] }

        var errors: [String] = []
        let targets = items

        for item in targets {
            do {
                switch operation {
                case .moveToSystemTrash:
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                case .permanentDelete:
                    try FileManager.default.removeItem(at: item.url)
                }
                items.removeAll { $0.id == item.id }
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        if !targets.isEmpty {
            invalidateTrashedPathsCache()
        }

        return errors
    }

    private func invalidateTrashedPathsCache() {
        cachedTrashedPaths = nil
        trashedPathsRevision &+= 1
        DiskNodeTrashCache.invalidateTrash()
    }
}
