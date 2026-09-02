import Foundation

enum DiskNodeAccessMetrics {
    static func inaccessibleSize(in node: DiskNode) -> Int64 {
        var total: Int64 = 0
        if node.name.hasPrefix("🔒") {
            total += node.size
        }
        for child in node.children {
            total += inaccessibleSize(in: child)
        }
        return total
    }

    static func inaccessibleDirectoryCount(in node: DiskNode) -> Int {
        var count = node.name.hasPrefix("🔒") && node.isDirectory ? 1 : 0
        for child in node.children {
            count += inaccessibleDirectoryCount(in: child)
        }
        return count
    }
}
