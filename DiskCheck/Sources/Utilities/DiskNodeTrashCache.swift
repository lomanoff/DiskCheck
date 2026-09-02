import Foundation

/// Кэш дорогих операций над деревом (фильтрация корзины, размеры, сегменты sunburst).
enum DiskNodeTrashCache {
    private struct NodeKey: Hashable {
        let nodeID: UUID
        let nodeSize: Int64
        let childCount: Int
        let trashRevision: Int
    }

    private nonisolated(unsafe) static var trashRevision = 0
    private nonisolated(unsafe) static var legendCache: [NodeKey: DiskNode] = [:]
    private nonisolated(unsafe) static var displaySizeCache: [NodeKey: Int64] = [:]
    private nonisolated(unsafe) static var segmentsCache: [NodeKey: [SunburstSegment]] = [:]

    static func invalidateTrash() {
        trashRevision &+= 1
        legendCache.removeAll(keepingCapacity: true)
        displaySizeCache.removeAll(keepingCapacity: true)
        segmentsCache.removeAll(keepingCapacity: true)
    }

    static func invalidateTree() {
        legendCache.removeAll(keepingCapacity: true)
        displaySizeCache.removeAll(keepingCapacity: true)
        segmentsCache.removeAll(keepingCapacity: true)
        DiskNodeDeletability.clearCache()
    }

    static func filteredForLegend(_ node: DiskNode, trashedPaths: Set<String>) -> DiskNode {
        let key = nodeKey(for: node)
        if let cached = legendCache[key] { return cached }
        let result = filteredForLegendUncached(node, trashedPaths: trashedPaths)
        legendCache[key] = result
        return result
    }

    static func displaySize(for node: DiskNode, trashedPaths: Set<String>) -> Int64 {
        let key = nodeKey(for: node)
        if let cached = displaySizeCache[key] { return cached }
        let result = displaySizeUncached(node, trashedPaths: trashedPaths)
        displaySizeCache[key] = result
        return result
    }

    static func sunburstSegments(for node: DiskNode, trashedPaths: Set<String>) -> [SunburstSegment] {
        let displayNode = filteredForLegend(node, trashedPaths: trashedPaths)
        let key = nodeKey(for: displayNode)
        if let cached = segmentsCache[key] { return cached }
        let result = SunburstLayout.segments(for: displayNode)
        segmentsCache[key] = result
        return result
    }

    private static func nodeKey(for node: DiskNode) -> NodeKey {
        NodeKey(
            nodeID: node.id,
            nodeSize: node.size,
            childCount: node.children.count,
            trashRevision: trashRevision
        )
    }

    private static func displaySizeUncached(_ node: DiskNode, trashedPaths: Set<String>) -> Int64 {
        if DiskNodeTrash.isTrashed(node, trashedPaths: trashedPaths) { return 0 }
        guard node.isDirectory, !node.children.isEmpty else { return node.size }

        let visibleSize = DiskNodeTrash.visibleChildren(of: node, trashedPaths: trashedPaths)
            .reduce(Int64(0)) { $0 + displaySizeUncached($1, trashedPaths: trashedPaths) }
        return max(node.size, visibleSize)
    }

    private static func filteredForLegendUncached(_ node: DiskNode, trashedPaths: Set<String>) -> DiskNode {
        var copy = node
        copy.children = DiskNodeTrash.visibleChildren(of: node, trashedPaths: trashedPaths)
            .map { filteredForLegendUncached($0, trashedPaths: trashedPaths) }

        let visibleSize = copy.children.reduce(Int64(0)) { $0 + $1.size }
        if copy.isDirectory {
            if copy.children.isEmpty {
                copy.size = node.size
            } else {
                copy.size = max(node.size, visibleSize)
            }
        }
        return copy
    }
}
