import Foundation

enum DiskCategoryClassifier {
    private static let buildArtifactNames: Set<String> = [
        ".build", "build", "target", "dist", "out",
        ".next", ".nuxt", ".output", ".turbo",
        "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        ".tox", ".nox", "coverage", ".coverage",
    ]

    private static let packageCacheNames: Set<String> = [
        ".npm", ".yarn", ".pnpm-store", ".pnpm", ".cargo",
        ".rustup", ".gem", ".bundle", ".m2", ".gradle",
        "Pods", "Carthage", "SourcePackages",
    ]

    private static let ideMetadataNames: Set<String> = [
        ".idea", ".vscode", ".vs", ".fleet", ".metals",
    ]

    static func buildIndex(root: DiskNode) -> CategoryIndex {
        var buckets: [DiskCategory: [CategorizedItem]] = [:]
        collect(from: root, into: &buckets)

        for category in DiskCategory.allCases {
            buckets[category] = (buckets[category] ?? [])
                .sorted { $0.node.size > $1.node.size }
        }

        return CategoryIndex(itemsByCategory: buckets, scannedAt: .now)
    }

    private static func collect(from node: DiskNode, into buckets: inout [DiskCategory: [CategorizedItem]]) {
        if let category = classify(node) {
            buckets[category, default: []].append(CategorizedItem(category: category, node: node))
            return
        }

        guard node.isDirectory else { return }
        for child in node.children {
            collect(from: child, into: &buckets)
        }
    }

    static func classify(_ node: DiskNode) -> DiskCategory? {
        if isNoSyncItem(node) {
            return .noSync
        }

        guard node.isDirectory else { return nil }

        let name = node.name
        let path = node.url.standardizedFileURL.path

        if isGitRepository(node) {
            return .gitRepositories
        }
        if name == "node_modules" {
            return .nodeModules
        }
        if isXcodeDerivedData(path: path) {
            return .xcodeDerivedData
        }
        if buildArtifactNames.contains(name) {
            return .buildArtifacts
        }
        if packageCacheNames.contains(name) || isPackageManagerCachePath(path) {
            return .packageManagerCaches
        }
        if isAppCache(node, path: path) {
            return .appCaches
        }
        if isLogDirectory(node, path: path) {
            return .logs
        }
        if ideMetadataNames.contains(name) {
            return .ideMetadata
        }

        return nil
    }

    private static func isXcodeDerivedData(path: String) -> Bool {
        path.hasSuffix("/Developer/Xcode/DerivedData")
    }

    private static func isNoSyncItem(_ node: DiskNode) -> Bool {
        let name = node.name
        if name == ".nosync" || name.hasSuffix(".nosync") {
            return true
        }

        guard node.isDirectory else { return false }

        if node.children.contains(where: { $0.name == ".nosync" && !$0.isDirectory }) {
            return true
        }

        var isDirectory: ObjCBool = false
        let markerURL = node.url.appendingPathComponent(".nosync")
        guard FileManager.default.fileExists(atPath: markerURL.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private static func isGitRepository(_ node: DiskNode) -> Bool {
        if node.children.contains(where: { $0.name == ".git" }) {
            return true
        }
        var isDirectory: ObjCBool = false
        let gitURL = node.url.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) else {
            return false
        }
        return true
    }

    private static func isPackageManagerCachePath(_ path: String) -> Bool {
        let markers = [
            "/Library/Caches/Homebrew",
            "/.cache/pip",
            "/.cache/go-build",
            "/go/pkg/mod",
            "/Library/Caches/CocoaPods",
            "/Library/Caches/com.apple.dt.Xcode",
        ]
        return markers.contains { path.hasSuffix($0) || path.contains($0 + "/") }
    }

    private static func isAppCache(_ node: DiskNode, path: String) -> Bool {
        guard path.contains("/Library/Caches") else { return false }
        if path.hasSuffix("/Library/Caches") { return true }

        let components = path.split(separator: "/")
        guard let cachesIndex = components.lastIndex(of: "Caches"),
              cachesIndex > 0,
              components[cachesIndex - 1] == "Library"
        else { return false }

        return components.count == cachesIndex + 2
    }

    private static func isLogDirectory(_ node: DiskNode, path: String) -> Bool {
        guard path.contains("/Library/Logs") else { return false }
        if path.hasSuffix("/Library/Logs") { return true }

        let components = path.split(separator: "/")
        guard let logsIndex = components.lastIndex(of: "Logs"),
              logsIndex > 0,
              components[logsIndex - 1] == "Library"
        else { return false }

        return components.count == logsIndex + 2
    }
}
