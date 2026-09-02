import Foundation

struct CachedScanNode: Codable, Sendable {
    let path: String
    let name: String
    let isDirectory: Bool
    let workUnits: Int
    let children: [CachedScanNode]
}

struct ScanTreeCacheEntry: Codable, Sendable {
    let rootPath: String
    let scannedAt: Date
    let totalWorkUnits: Int
    let root: CachedScanNode
}

enum ScanWorkEstimator {
    static func workUnits(for node: DiskNode) -> Int {
        if !node.isDirectory {
            return 1
        }
        if node.children.isEmpty {
            return max(1, Int(node.size / (50 * 1024 * 1024)) + 1)
        }
        return 1 + node.children.reduce(0) { $0 + workUnits(for: $1) }
    }

    static func buildCache(root: DiskNode) -> ScanTreeCacheEntry {
        let cachedRoot = makeCachedNode(from: root)
        return ScanTreeCacheEntry(
            rootPath: root.url.standardizedFileURL.path,
            scannedAt: .now,
            totalWorkUnits: cachedRoot.workUnits,
            root: cachedRoot
        )
    }

    private static func makeCachedNode(from node: DiskNode) -> CachedScanNode {
        CachedScanNode(
            path: node.url.standardizedFileURL.path,
            name: node.name,
            isDirectory: node.isDirectory,
            workUnits: workUnits(for: node),
            children: node.children.map { makeCachedNode(from: $0) }
        )
    }

    static func quickEstimateWorkUnits(at url: URL) -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return 1 }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: []
        ) else { return 500 }

        var estimate = max(contents.count * 80, 200)

        for child in contents.prefix(6) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isDir = values?.isDirectory == true
            let isPackage = values?.isPackage == true
            guard isDir, !isPackage else { continue }

            if let subcontents = try? FileManager.default.contentsOfDirectory(
                at: child,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) {
                estimate += subcontents.count * 12
            }
        }

        return max(estimate, 200)
    }

    static func estimateWorkUnits(
        at url: URL,
        maxDepth: Int,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> Int {
        await Task.detached {
            var total = 0
            countWork(at: url, depth: 0, maxDepth: maxDepth, total: &total, onProgress: onProgress)
            return max(total, 1)
        }.value
    }

    private static func reportProgress(total: Int, onProgress: (@Sendable (Int) -> Void)?) {
        guard total > 0, total % 2_000 == 0 else { return }
        onProgress?(total)
    }

    private static func countWork(
        at url: URL,
        depth: Int,
        maxDepth: Int,
        total: inout Int,
        onProgress: (@Sendable (Int) -> Void)?
    ) {
        total += 1
        reportProgress(total: total, onProgress: onProgress)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }

        if depth >= maxDepth {
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) {
                for case let item as URL in enumerator {
                    total += 1
                    reportProgress(total: total, onProgress: onProgress)
                }
            }
            return
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: []
        ) else { return }

        for child in contents {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isDir = values?.isDirectory == true
            let isPackage = values?.isPackage == true

            if isDir, !isPackage {
                countWork(at: child, depth: depth + 1, maxDepth: maxDepth, total: &total, onProgress: onProgress)
            } else {
                total += 1
                reportProgress(total: total, onProgress: onProgress)
            }
        }
    }
}
