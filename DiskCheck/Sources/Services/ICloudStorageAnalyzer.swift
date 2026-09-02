import Foundation

enum ICloudStorageAnalyzer {
    private static let mobileDocumentsMarker = "/Library/Mobile Documents"
    private static let cloudDocsMarker = "com~apple~CloudDocs"

    static func analyze(root: DiskNode, categoryIndex: CategoryIndex) -> ICloudStorageSummary {
        let nosyncItems = categoryIndex.items(for: .noSync)
        var mobileSize: Int64 = 0
        var mobileCount = 0
        var driveSize: Int64 = 0

        collectMobileDocumentsMetrics(from: root) { node, kind in
            switch kind {
            case .mobileDocuments:
                mobileSize += node.size
                mobileCount += 1
            case .iCloudDrive:
                driveSize += node.size
            }
        }

        return ICloudStorageSummary(
            nosyncSize: nosyncItems.reduce(0) { $0 + $1.node.size },
            nosyncCount: nosyncItems.count,
            mobileDocumentsSize: mobileSize,
            mobileDocumentsCount: mobileCount,
            iCloudDriveSize: driveSize,
            locallyStoredSize: 0,
            cloudOnlySize: 0
        )
    }

    static func enrichWithUbiquityAttributes(_ summary: ICloudStorageSummary) async -> ICloudStorageSummary {
        let mobileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents", isDirectory: true)

        guard FileManager.default.fileExists(atPath: mobileURL.path) else {
            return summary
        }

        let footprint = await scanUbiquitousFootprint(at: mobileURL)
        return ICloudStorageSummary(
            nosyncSize: summary.nosyncSize,
            nosyncCount: summary.nosyncCount,
            mobileDocumentsSize: max(summary.mobileDocumentsSize, footprint.totalSize),
            mobileDocumentsCount: max(summary.mobileDocumentsCount, footprint.itemCount),
            iCloudDriveSize: summary.iCloudDriveSize,
            locallyStoredSize: footprint.locallyStoredSize,
            cloudOnlySize: footprint.cloudOnlySize
        )
    }

    private enum MobilePathKind {
        case mobileDocuments
        case iCloudDrive
    }

    private struct UbiquitousFootprint {
        var totalSize: Int64 = 0
        var itemCount = 0
        var locallyStoredSize: Int64 = 0
        var cloudOnlySize: Int64 = 0
    }

    private static func collectMobileDocumentsMetrics(
        from node: DiskNode,
        onMatch: (DiskNode, MobilePathKind) -> Void
    ) {
        let path = node.url.standardizedFileURL.path
        if path.contains(cloudDocsMarker) {
            onMatch(node, .iCloudDrive)
            return
        }
        if path.contains(mobileDocumentsMarker) {
            onMatch(node, .mobileDocuments)
            return
        }

        guard node.isDirectory else { return }
        for child in node.children {
            collectMobileDocumentsMetrics(from: child, onMatch: onMatch)
        }
    }

    private static func scanUbiquitousFootprint(at rootURL: URL) async -> UbiquitousFootprint {
        await Task.detached(priority: .utility) {
            scanUbiquitousFootprintSync(at: rootURL)
        }.value
    }

    private static func scanUbiquitousFootprintSync(at rootURL: URL) -> UbiquitousFootprint {
        var footprint = UbiquitousFootprint()
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return footprint }

        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }

            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            guard size > 0 else { continue }

            footprint.itemCount += 1
            footprint.totalSize += size

            guard values.isUbiquitousItem == true else { continue }

            switch values.ubiquitousItemDownloadingStatus {
            case .current, .downloaded:
                footprint.locallyStoredSize += size
            case .notDownloaded:
                footprint.cloudOnlySize += size
            default:
                footprint.locallyStoredSize += size
            }
        }

        return footprint
    }
}
