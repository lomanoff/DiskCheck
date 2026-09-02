import Foundation

enum DiskNodeDeletability {
    private static let protectedPrefixes = [
        "/System/Volumes/Data/System",
        "/System/Volumes/Data/Library",
        "/System/Volumes/Data/usr",
        "/System/Volumes/Data/bin",
        "/System/Volumes/Data/sbin",
        "/System/Volumes/Data/etc",
        "/System/Volumes/Data/var/db",
        "/System/Volumes/Data/var/root",
        "/System/Volumes/Data/var/protected",
        "/System/Volumes/Data/private/var/db",
        "/System/Volumes/Data/private/etc",
        "/System/Volumes/Data/.DocumentRevisions-V100",
        "/System/Volumes/Data/.fseventsd",
        "/System/Volumes/Data/.Spotlight-V100",
        "/System/Volumes/Data/cores",
        "/System/Volumes/Data/dev",
        "/System/Volumes/Data/home",
        "/System/Volumes/Data/Volumes",
        "/System/Volumes/Data/mnt",
        "/System/Volumes/Data/MobileSoftwareUpdate",
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/var/db",
        "/private/var/db",
    ]

    private nonisolated(unsafe) static var listedAsDeletableCache: [String: Bool] = [:]
    private nonisolated(unsafe) static var directlyDeletableCache: [String: Bool] = [:]
    private nonisolated(unsafe) static var groupedChildrenCache: [GroupedChildrenKey: (deletable: [DiskNode], protected: [DiskNode])] = [:]

    private struct GroupedChildrenKey: Hashable {
        let childSignature: String
    }

    static func clearCache() {
        listedAsDeletableCache.removeAll(keepingCapacity: true)
        directlyDeletableCache.removeAll(keepingCapacity: true)
        groupedChildrenCache.removeAll(keepingCapacity: true)
    }

    /// Показывать в секции «Можно удалить», если сам элемент или что-то внутри можно удалить.
    static func isListedAsDeletable(_ node: DiskNode) -> Bool {
        let path = node.url.standardizedFileURL.path
        if let cached = listedAsDeletableCache[path] { return cached }
        let result = isListedAsDeletableUncached(node)
        listedAsDeletableCache[path] = result
        return result
    }

    /// Можно положить именно этот элемент в корзину.
    static func canStageForDeletion(_ node: DiskNode) -> Bool {
        isDirectlyDeletable(node)
    }

    static func groupedChildren(_ children: [DiskNode]) -> (deletable: [DiskNode], protected: [DiskNode]) {
        let signature = children
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString):\($0.size)" }
            .joined(separator: "|")
        let key = GroupedChildrenKey(childSignature: signature)

        if let cached = groupedChildrenCache[key] { return cached }

        let sorted = children.sorted { $0.size > $1.size }
        var deletable: [DiskNode] = []
        var protected: [DiskNode] = []

        for child in sorted {
            if isListedAsDeletable(child) {
                deletable.append(child)
            } else {
                protected.append(child)
            }
        }

        let result = (deletable, protected)
        groupedChildrenCache[key] = result
        return result
    }

    private static func isListedAsDeletableUncached(_ node: DiskNode) -> Bool {
        if isDirectlyDeletable(node) { return true }
        guard node.isDirectory, !node.children.isEmpty else { return false }
        return node.children.contains { isListedAsDeletable($0) }
    }

    private static func isDirectlyDeletable(_ node: DiskNode) -> Bool {
        let path = node.url.standardizedFileURL.path
        if let cached = directlyDeletableCache[path] { return cached }

        if node.name.hasPrefix("🔒") {
            directlyDeletableCache[path] = false
            return false
        }

        if isProtectedPath(path) {
            directlyDeletableCache[path] = false
            return false
        }

        let result = FileManager.default.isWritableFile(atPath: path)
            || FileManager.default.isWritableFile(atPath: node.url.deletingLastPathComponent().path)
        directlyDeletableCache[path] = result
        return result
    }

    private static func isProtectedPath(_ path: String) -> Bool {
        if path == "/System/Volumes/Data/Applications" { return false }
        if path == "/System/Volumes/Data/Users" { return false }

        return protectedPrefixes.contains { prefix in
            path == prefix || path.hasPrefix(prefix + "/")
        }
    }
}
