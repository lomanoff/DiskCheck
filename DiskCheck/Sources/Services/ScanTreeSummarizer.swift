import Foundation

enum ScanTreeSummarizer {
    struct SummaryEntry: Sendable {
        let path: String
        let name: String
        let size: Int64
        let isDirectory: Bool
        let tags: [String]
    }

    struct Summary: Sendable {
        let rootPath: String
        let rootSize: Int64
        let entries: [SummaryEntry]
        let ruleBasedHits: [String]
    }

    static func summarize(root: DiskNode, categoryIndex: CategoryIndex, limit: Int = 100) -> Summary {
        var entries: [SummaryEntry] = []
        collectEntries(from: root, depth: 0, maxDepth: 4, limit: limit, into: &entries)

        let ruleHits = ruleBasedPaths(in: categoryIndex)

        for path in ruleHits where !entries.contains(where: { $0.path == path }) {
            if let node = findNode(path: path, in: root) {
                entries.append(SummaryEntry(
                    path: path,
                    name: node.name,
                    size: node.size,
                    isDirectory: node.isDirectory,
                    tags: ["rule"]
                ))
            }
        }

        return finalizeSummary(root: root, entries: entries, ruleHits: ruleHits, limit: limit)
    }

    static func summarizeRemaining(
        root: DiskNode,
        excludingPaths: Set<String>,
        limit: Int = 400
    ) -> Summary {
        var entries: [SummaryEntry] = []
        collectAllEntries(from: root, depth: 0, maxDepth: 8, limit: limit * 3, into: &entries)

        let standardizedExclusions = Set(excludingPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })

        entries = entries.filter { !standardizedExclusions.contains($0.path) }
        return finalizeSummary(root: root, entries: entries, ruleHits: [], limit: limit)
    }

    static func paths(from summary: Summary) -> Set<String> {
        Set(summary.entries.map(\.path))
    }

    private static func ruleBasedPaths(in categoryIndex: CategoryIndex) -> [String] {
        DiskCategory.allCases.flatMap { category in
            categoryIndex.items(for: category).map(\.node.url.path)
        }
    }

    private static func finalizeSummary(
        root: DiskNode,
        entries: [SummaryEntry],
        ruleHits: [String],
        limit: Int
    ) -> Summary {
        var entries = entries
        entries.sort { $0.size > $1.size }
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }

        return Summary(
            rootPath: root.url.standardizedFileURL.path,
            rootSize: root.size,
            entries: entries,
            ruleBasedHits: Array(Set(ruleHits)).sorted()
        )
    }

    static func promptText(from summary: Summary, scope: AIAdviceScope = .overview) -> String {
        var lines: [String] = []
        lines.append("Корень: \(summary.rootPath)")
        lines.append("Размер: \(summary.rootSize) байт")
        lines.append("")
        switch scope {
        case .overview:
            lines.append("Кандидаты (path | size_bytes | dir | name):")
        case .remainingFiles:
            lines.append("Дополнительные кандидаты вне основного обзора (path | size_bytes | dir | name):")
        }
        for entry in summary.entries {
            lines.append("\(entry.path) | \(entry.size) | \(entry.isDirectory ? 1 : 0) | \(entry.name)")
        }
        if !summary.ruleBasedHits.isEmpty {
            lines.append("")
            lines.append("Уже найдено правилами:")
            for path in summary.ruleBasedHits.prefix(40) {
                lines.append(path)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func findNode(path: String, in root: DiskNode) -> DiskNode? {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        if root.url.standardizedFileURL.path == target { return root }
        return findNodeRecursive(target: target, in: root)
    }

    private static func findNodeRecursive(target: String, in node: DiskNode) -> DiskNode? {
        for child in node.children {
            if child.url.standardizedFileURL.path == target { return child }
            if let found = findNodeRecursive(target: target, in: child) {
                return found
            }
        }
        return nil
    }

    private static func collectEntries(
        from node: DiskNode,
        depth: Int,
        maxDepth: Int,
        limit: Int,
        into entries: inout [SummaryEntry]
    ) {
        guard entries.count < limit else { return }

        let path = node.url.standardizedFileURL.path
        if depth > 0 || node.children.isEmpty {
            entries.append(SummaryEntry(
                path: path,
                name: node.name,
                size: node.size,
                isDirectory: node.isDirectory,
                tags: []
            ))
        }

        guard node.isDirectory, depth < maxDepth else { return }
        for child in node.sortedChildren.prefix(30) {
            collectEntries(from: child, depth: depth + 1, maxDepth: maxDepth, limit: limit, into: &entries)
            if entries.count >= limit { return }
        }
    }

    private static func collectAllEntries(
        from node: DiskNode,
        depth: Int,
        maxDepth: Int,
        limit: Int,
        into entries: inout [SummaryEntry]
    ) {
        guard entries.count < limit else { return }

        let path = node.url.standardizedFileURL.path
        if depth > 0 {
            entries.append(SummaryEntry(
                path: path,
                name: node.name,
                size: node.size,
                isDirectory: node.isDirectory,
                tags: []
            ))
        }

        guard node.isDirectory, depth < maxDepth else { return }
        for child in node.sortedChildren {
            collectAllEntries(from: child, depth: depth + 1, maxDepth: maxDepth, limit: limit, into: &entries)
            if entries.count >= limit { return }
        }
    }
}
