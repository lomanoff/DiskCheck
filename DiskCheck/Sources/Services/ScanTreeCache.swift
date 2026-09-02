import Foundation

enum ScanTreeCache {
    private static let directoryName = "scan-cache"

    static func load(rootPath: String) -> ScanTreeCacheEntry? {
        let standardizedRoot = standardizedPath(rootPath)
        let url = cacheFileURL(for: standardizedRoot)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(ScanTreeCacheEntry.self, from: data)
        else { return nil }

        guard isValid(entry, forRootPath: standardizedRoot) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return entry
    }

    static func isValid(_ entry: ScanTreeCacheEntry, forRootPath rootPath: String) -> Bool {
        let expected = standardizedPath(rootPath)
        let cachedRoot = standardizedPath(entry.rootPath)

        guard cachedRoot == expected else { return false }
        guard entry.totalWorkUnits > 0 else { return false }
        guard entry.root.workUnits > 0 else { return false }
        guard standardizedPath(entry.root.path) == cachedRoot else { return false }

        if entry.root.isDirectory, entry.root.children.isEmpty, entry.totalWorkUnits <= 1 {
            return false
        }

        return true
    }

    static func save(_ entry: ScanTreeCacheEntry) {
        guard isValid(entry, forRootPath: entry.rootPath) else { return }

        let directory = cacheDirectoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = cacheFileURL(for: entry.rootPath)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func remove(rootPath: String) {
        let url = cacheFileURL(for: standardizedPath(rootPath))
        try? FileManager.default.removeItem(at: url)
    }

    static func workUnits(for path: String, in entry: ScanTreeCacheEntry) -> Int? {
        findNode(path: standardizedPath(path), in: entry.root)?.workUnits
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func findNode(path: String, in node: CachedScanNode) -> CachedScanNode? {
        let nodePath = standardizedPath(node.path)
        if nodePath == path { return node }
        for child in node.children {
            if let found = findNode(path: path, in: child) {
                return found
            }
        }
        return nil
    }

    private static func cacheDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("DiskCheck", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func cacheFileURL(for rootPath: String) -> URL {
        let key = standardizedPath(rootPath).data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_") ?? "root"
        return cacheDirectoryURL().appendingPathComponent("\(key).json")
    }
}
