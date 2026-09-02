import Foundation

enum DiskNodeTrash {
    static func pathIsTrashed(_ path: String, trashedPaths: Set<String>) -> Bool {
        trashedPaths.contains { itemPath in
            path == itemPath || path.hasPrefix(itemPath + "/")
        }
    }

    static func isTrashed(_ node: DiskNode, trashedPaths: Set<String>) -> Bool {
        pathIsTrashed(node.url.standardizedFileURL.path, trashedPaths: trashedPaths)
    }

    static func visibleChildren(of node: DiskNode, trashedPaths: Set<String>) -> [DiskNode] {
        node.sortedChildren.filter { !isTrashed($0, trashedPaths: trashedPaths) }
    }

    /// Размер для UI: не занижает результат сканирования и учитывает корзину.
    static func displaySize(for node: DiskNode, trashedPaths: Set<String>) -> Int64 {
        DiskNodeTrashCache.displaySize(for: node, trashedPaths: trashedPaths)
    }

    /// Дерево для легенды: скрывает помеченные элементы и пересчитывает размер.
    static func filteredForLegend(_ node: DiskNode, trashedPaths: Set<String>) -> DiskNode {
        DiskNodeTrashCache.filteredForLegend(node, trashedPaths: trashedPaths)
    }
}
