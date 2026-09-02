import XCTest
@testable import DiskCheck

final class SunburstLayoutTests: XCTestCase {
    func testSegmentsCoverFullCircle() {
        let root = makeTestTree()
        let segments = SunburstLayout.segments(for: root)

        let depth1 = segments.filter { $0.depth == 1 }
        XCTAssertEqual(depth1.count, 3)

        let totalSpan = depth1.reduce(0.0) { $0 + ($1.endAngle - $1.startAngle) }
        XCTAssertEqual(totalSpan, 2 * .pi, accuracy: 0.001)
    }

    func testDeletableGrouping() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let tree = DiskNode(
            url: URL(fileURLWithPath: home),
            name: "Home",
            size: 1000,
            children: [
                DiskNode(url: URL(fileURLWithPath: "\(home)/Documents"), name: "Documents", size: 500),
                DiskNode(url: URL(fileURLWithPath: "/System/Volumes/Data/Library"), name: "Library", size: 300),
            ]
        )

        let groups = DiskNodeDeletability.groupedChildren(tree.children)
        XCTAssertEqual(groups.deletable.count, 1)
        XCTAssertEqual(groups.protected.count, 1)
        XCTAssertEqual(groups.deletable.first?.name, "Documents")
        XCTAssertEqual(groups.protected.first?.name, "Library")
    }

    func testUsersListedAsDeletableWhenDescendantsAreDeletable() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let users = DiskNode(
            url: URL(fileURLWithPath: "/System/Volumes/Data/Users"),
            name: "Users",
            size: 1000,
            children: [
                DiskNode(
                    url: URL(fileURLWithPath: home),
                    name: "alomanov",
                    size: 800,
                    children: [
                        DiskNode(url: URL(fileURLWithPath: "\(home)/Documents"), name: "Documents", size: 500),
                    ]
                ),
            ]
        )

        XCTAssertTrue(DiskNodeDeletability.isListedAsDeletable(users))
        XCTAssertFalse(DiskNodeDeletability.canStageForDeletion(users))
    }

    func testFullyProtectedFolderStaysProtected() {
        let library = DiskNode(
            url: URL(fileURLWithPath: "/System/Volumes/Data/Library"),
            name: "Library",
            size: 300,
            children: [
                DiskNode(url: URL(fileURLWithPath: "/System/Volumes/Data/Library/Preferences"), name: "Preferences", size: 100),
            ]
        )

        XCTAssertFalse(DiskNodeDeletability.isListedAsDeletable(library))
    }

    func testScanCacheRoundTrip() {
        let rootPath = "/tmp/diskcheck-cache-test-\(UUID().uuidString)"
        let root = DiskNode(
            url: URL(fileURLWithPath: rootPath),
            name: "Root",
            size: 1000,
            children: [
                DiskNode(url: URL(fileURLWithPath: "\(rootPath)/a"), name: "A", size: 500),
            ]
        )
        let entry = ScanWorkEstimator.buildCache(root: root)
        ScanTreeCache.save(entry)

        let loaded = ScanTreeCache.load(rootPath: rootPath)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.totalWorkUnits, entry.totalWorkUnits)
    }

    func testInvalidEmptyCacheIsRejected() {
        let rootPath = "/System/Volumes/Data"
        let entry = ScanTreeCacheEntry(
            rootPath: rootPath,
            scannedAt: .now,
            totalWorkUnits: 1,
            root: CachedScanNode(
                path: rootPath,
                name: "Data",
                isDirectory: true,
                workUnits: 1,
                children: []
            )
        )

        XCTAssertFalse(ScanTreeCache.isValid(entry, forRootPath: rootPath))
    }

    func testDeletionAdviceParser() {
        let rootPath = "/tmp/diskcheck-ai-\(UUID().uuidString)"
        let childPath = "\(rootPath)/Caches"
        let root = DiskNode(
            url: URL(fileURLWithPath: rootPath),
            name: "Root",
            size: 1000,
            children: [
                DiskNode(url: URL(fileURLWithPath: childPath), name: "Caches", size: 400),
            ]
        )

        let json = """
        {
          "categories": [
            {
              "title": "Кэши",
              "rationale": "Можно очистить",
              "safety": "safe",
              "paths": ["\(childPath)"]
            }
          ]
        }
        """

        let categories = DeletionAdviceParser.parse(
            jsonText: json,
            root: root,
            allowedPaths: [childPath]
        )

        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories.first?.items.count, 1)
        XCTAssertEqual(categories.first?.items.first?.node.name, "Caches")
    }

    func testCategoryClassifierDetectsCommonTargets() {
        let projectPath = "/tmp/diskcheck-categories-\(UUID().uuidString)"
        let root = DiskNode(
            url: URL(fileURLWithPath: projectPath),
            name: "Projects",
            size: 10_000,
            children: [
                DiskNode(
                    url: URL(fileURLWithPath: "\(projectPath)/my-app"),
                    name: "my-app",
                    size: 5000,
                    children: [
                        DiskNode(
                            url: URL(fileURLWithPath: "\(projectPath)/my-app/.git"),
                            name: ".git",
                            size: 200
                        ),
                        DiskNode(
                            url: URL(fileURLWithPath: "\(projectPath)/my-app/node_modules"),
                            name: "node_modules",
                            size: 3000
                        ),
                    ]
                ),
                DiskNode(
                    url: URL(fileURLWithPath: "\(projectPath)/node_modules"),
                    name: "node_modules",
                    size: 4000
                ),
                DiskNode(
                    url: URL(fileURLWithPath: "\(projectPath)/DerivedData"),
                    name: "DerivedData",
                    size: 900
                ),
                DiskNode(
                    url: URL(fileURLWithPath: "\(projectPath)/Library/Developer/Xcode/DerivedData"),
                    name: "DerivedData",
                    size: 2000
                ),
                DiskNode(
                    url: URL(fileURLWithPath: "\(projectPath)/Library/Caches/com.example.app"),
                    name: "com.example.app",
                    size: 800
                ),
                DiskNode(
                    url: URL(fileURLWithPath: "\(projectPath)/Photos.nosync"),
                    name: "Photos.nosync",
                    size: 1500
                ),
                DiskNode(
                    url: URL(fileURLWithPath: "\(projectPath)/iCloudBackup"),
                    name: "iCloudBackup",
                    size: 900,
                    children: [
                        DiskNode(
                            url: URL(fileURLWithPath: "\(projectPath)/iCloudBackup/.nosync"),
                            name: ".nosync",
                            size: 0,
                            isDirectory: false
                        ),
                    ]
                ),
            ]
        )

        let index = DiskCategoryClassifier.buildIndex(root: root)

        XCTAssertEqual(index.items(for: .gitRepositories).count, 1)
        XCTAssertEqual(index.items(for: .gitRepositories).first?.node.name, "my-app")
        XCTAssertEqual(index.items(for: .nodeModules).count, 1)
        XCTAssertEqual(index.items(for: .nodeModules).first?.node.name, "node_modules")
        XCTAssertEqual(index.items(for: .noSync).count, 2)
        XCTAssertEqual(index.items(for: .xcodeDerivedData).count, 1)
        XCTAssertEqual(
            index.items(for: .xcodeDerivedData).first?.node.url.path,
            "\(projectPath)/Library/Developer/Xcode/DerivedData"
        )
        XCTAssertFalse(
            index.items(for: .xcodeDerivedData).contains {
                $0.node.url.path == "\(projectPath)/DerivedData"
            }
        )
        XCTAssertEqual(index.items(for: .appCaches).count, 1)
        XCTAssertEqual(index.totalSize(for: .gitRepositories), 5000)
        XCTAssertEqual(index.totalSize(for: .nodeModules), 4000)
    }

    func testQuickEstimateUsesShallowDirectoryProbe() {
        let rootPath = "/tmp/diskcheck-quick-estimate-\(UUID().uuidString)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: rootPath, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(rootPath)/alpha", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(rootPath)/beta", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: rootPath) }

        let estimate = ScanWorkEstimator.quickEstimateWorkUnits(at: URL(fileURLWithPath: rootPath))

        XCTAssertGreaterThanOrEqual(estimate, 200)
        XCTAssertLessThan(estimate, 10_000)
    }

    func testSummarizeRemainingExcludesOverviewPaths() {
        let rootPath = "/tmp/diskcheck-remaining-\(UUID().uuidString)"
        let root = DiskNode(
            url: URL(fileURLWithPath: rootPath),
            name: "Root",
            size: 10_000,
            children: [
                DiskNode(url: URL(fileURLWithPath: "\(rootPath)/large"), name: "large", size: 8000),
                DiskNode(url: URL(fileURLWithPath: "\(rootPath)/small"), name: "small", size: 1000),
            ]
        )

        let overview = ScanTreeSummarizer.summarize(root: root, categoryIndex: .empty, limit: 1)
        let remaining = ScanTreeSummarizer.summarizeRemaining(
            root: root,
            excludingPaths: ScanTreeSummarizer.paths(from: overview)
        )

        XCTAssertEqual(overview.entries.count, 1)
        XCTAssertEqual(overview.entries.first?.name, "large")
        XCTAssertTrue(remaining.entries.contains(where: { $0.name == "small" }))
        XCTAssertFalse(remaining.entries.contains(where: { $0.name == "large" }))
    }

    func testScannerCountsNestedPackageLikeDirectory() async throws {
        let fm = FileManager.default
        let rootPath = "/tmp/diskcheck-scanner-\(UUID().uuidString)"
        let bundlePath = "\(rootPath)/Sample.app/Contents/Resources"
        try fm.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 50_000).write(to: URL(fileURLWithPath: "\(bundlePath)/asset.bin"))
        try Data(repeating: 0xCD, count: 30_000).write(to: URL(fileURLWithPath: "\(rootPath)/loose.dat"))
        defer { try? fm.removeItem(atPath: rootPath) }

        let scanner = DiskScanner()
        let node = try await scanner.scan(url: URL(fileURLWithPath: rootPath))

        XCTAssertGreaterThanOrEqual(node.size, 80_000)
        XCTAssertTrue(node.children.contains(where: { $0.name == "Sample.app" }))
        let bundle = node.children.first(where: { $0.name == "Sample.app" })
        XCTAssertGreaterThanOrEqual(bundle?.size ?? 0, 50_000)
    }

    func testFilteredForLegendKeepsParentSizeWithoutSyntheticGap() {
        let path = "/tmp/diskcheck-legend-\(UUID().uuidString)"
        let node = DiskNode(
            url: URL(fileURLWithPath: path),
            name: "DerivedData",
            size: 48_000_000_000,
            children: [
                DiskNode(url: URL(fileURLWithPath: "\(path)/a"), name: "a", size: 4_000_000_000),
                DiskNode(url: URL(fileURLWithPath: "\(path)/b"), name: "b", size: 3_000_000_000),
            ]
        )

        let filtered = DiskNodeTrash.filteredForLegend(node, trashedPaths: [])
        XCTAssertEqual(filtered.size, 48_000_000_000)
        XCTAssertFalse(filtered.children.contains(where: { $0.name == "🔒 Не отображено в списке" }))
        XCTAssertEqual(filtered.children.count, 2)
    }

    func testFilteredForLegendKeepsSizeWhenChildrenMissing() {
        let path = "/tmp/diskcheck-legend-empty-\(UUID().uuidString)"
        let node = DiskNode(
            url: URL(fileURLWithPath: path),
            name: "🔒 DerivedData",
            size: 12_000_000_000,
            children: []
        )

        let filtered = DiskNodeTrash.filteredForLegend(node, trashedPaths: [])
        XCTAssertEqual(filtered.size, 12_000_000_000)
    }

    private func makeTestTree() -> DiskNode {
        DiskNode(
            url: URL(fileURLWithPath: "/"),
            name: "Root",
            size: 1000,
            children: [
                DiskNode(url: URL(fileURLWithPath: "/a"), name: "A", size: 500, colorIndex: 0),
                DiskNode(url: URL(fileURLWithPath: "/b"), name: "B", size: 300, colorIndex: 1),
                DiskNode(url: URL(fileURLWithPath: "/c"), name: "C", size: 200, colorIndex: 2),
            ],
            colorIndex: 0
        )
    }
}
