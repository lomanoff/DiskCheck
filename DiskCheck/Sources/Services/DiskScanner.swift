import Foundation

final class DiskScanner: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let minimumDisplaySize: Int64 = 1
    private let maxTreeDepth = 8
    private let deferScanThreshold: Int64 = 100 * 1024 * 1024
    private let concurrencyLimiter: ScanConcurrencyLimiter
    let maxConcurrentScans: Int

    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .fileResourceIdentifierKey,
    ]

    init(maxConcurrentDirectoryScans: Int? = nil) {
        let cpus = ProcessInfo.processInfo.activeProcessorCount
        let limit = maxConcurrentDirectoryScans ?? max(4, min(cpus, 12))
        maxConcurrentScans = limit
        concurrencyLimiter = ScanConcurrencyLimiter(permits: limit)
    }

    func scan(
        url: URL,
        cache: ScanTreeCacheEntry? = nil,
        previewRootID: UUID? = nil,
        volumeUsedTarget: Int64? = nil,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        onPartialRoot: (@Sendable (DiskNode) -> Void)? = nil,
        onActivity: (@Sendable (ScanActivitySnapshot) -> Void)? = nil
    ) async throws -> DiskNode {
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ScanError.pathNotFound(url)
        }

        let rootPath = url.standardizedFileURL.path
        let validatedCache: ScanTreeCacheEntry?
        if let cache, ScanTreeCache.isValid(cache, forRootPath: rootPath) {
            validatedCache = cache
        } else {
            if cache != nil {
                ScanTreeCache.remove(rootPath: rootPath)
            }
            validatedCache = nil
        }

        onProgress?(ScanProgress(
            currentItem: "Сканирование…",
            completed: 0,
            total: 1,
            phase: .scanning,
            discoveredBytes: 0,
            volumeUsedTarget: volumeUsedTarget
        ))

        let totalUnits: Int
        let usesDynamicTotal: Bool
        if let validatedCache {
            totalUnits = validatedCache.totalWorkUnits
            usesDynamicTotal = false
        } else {
            totalUnits = ScanWorkEstimator.quickEstimateWorkUnits(at: url)
            usesDynamicTotal = true
        }

        let tracker = WeightedProgressTracker(
            totalUnits: totalUnits,
            cache: validatedCache,
            usesDynamicTotal: usesDynamicTotal,
            volumeUsedTarget: volumeUsedTarget,
            onProgress: onProgress
        )
        let activityTracker = ScanActivityTracker(maxLanes: maxConcurrentScans, onUpdate: onActivity)
        let inodeRegistry = ScanInodeRegistry()
        let partialEmitter = PartialRootEmitter { partial in
            tracker.setDiscoveredBytes(partial.size)
            onPartialRoot?(partial)
        }
        let resolvedPreviewRootID = previewRootID ?? UUID()

        if isDirectory.boolValue {
            partialEmitter.emit(
                DiskNode(
                    id: resolvedPreviewRootID,
                    url: url,
                    name: name,
                    size: 0,
                    children: [],
                    isDirectory: true,
                    colorIndex: 0
                ),
                force: true
            )
            let rootPreview = RootPreviewCoordinator(
                url: url,
                name: name,
                colorIndex: 0,
                previewRootID: resolvedPreviewRootID,
                emitter: partialEmitter
            )
            let root = try await scanDirectory(
                url: url,
                name: name,
                depth: 0,
                colorIndex: 0,
                tracker: tracker,
                activityTracker: activityTracker,
                inodeRegistry: inodeRegistry,
                partialEmitter: partialEmitter,
                rootPreview: rootPreview
            )
            let deduplicatedRoot = rootWithUniqueSize(root, inodeRegistry: inodeRegistry)
            partialEmitter.emit(deduplicatedRoot, force: true)
            tracker.complete()
            return deduplicatedRoot
        }

        tracker.advance(1, item: name)
        tracker.complete()
        let size = fileSize(at: url, inodeRegistry: inodeRegistry)
        return DiskNode(url: url, name: name, size: size, isDirectory: false)
    }

    func scanSubtree(
        at url: URL,
        colorIndex: Int,
        onActivity: (@Sendable (ScanActivitySnapshot) -> Void)? = nil
    ) async throws -> DiskNode {
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let tracker = WeightedProgressTracker(
            totalUnits: ScanWorkEstimator.quickEstimateWorkUnits(at: url),
            cache: nil,
            onProgress: nil
        )
        let activityTracker = ScanActivityTracker(maxLanes: maxConcurrentScans, onUpdate: onActivity)
        let inodeRegistry = ScanInodeRegistry()
        let partialEmitter = PartialRootEmitter(handler: nil)

        let node = try await scanDirectory(
            url: url,
            name: name,
            depth: 0,
            colorIndex: colorIndex,
            tracker: tracker,
            activityTracker: activityTracker,
            inodeRegistry: inodeRegistry,
            partialEmitter: partialEmitter
        )
        return rootWithUniqueSize(node, inodeRegistry: inodeRegistry)
    }

    private func scanDirectory(
        url: URL,
        name: String,
        depth: Int,
        colorIndex: Int,
        tracker: WeightedProgressTracker,
        activityTracker: ScanActivityTracker,
        inodeRegistry: ScanInodeRegistry,
        partialEmitter: PartialRootEmitter,
        rootPreview: RootPreviewCoordinator? = nil,
        inProgressTopLevel: InProgressTopLevel? = nil
    ) async throws -> DiskNode {
        try await scanDirectoryImpl(
            url: url,
            name: name,
            depth: depth,
            colorIndex: colorIndex,
            tracker: tracker,
            activityTracker: activityTracker,
            inodeRegistry: inodeRegistry,
            partialEmitter: partialEmitter,
            rootPreview: rootPreview,
            inProgressTopLevel: inProgressTopLevel
        )
    }

    private func scanDirectoryImpl(
        url: URL,
        name: String,
        depth: Int,
        colorIndex: Int,
        tracker: WeightedProgressTracker,
        activityTracker: ScanActivityTracker,
        inodeRegistry: ScanInodeRegistry,
        partialEmitter: PartialRootEmitter,
        rootPreview: RootPreviewCoordinator? = nil,
        inProgressTopLevel: InProgressTopLevel? = nil
    ) async throws -> DiskNode {
        tracker.report(currentItem: name)

        let contents = await concurrencyLimiter.withPermitSync {
            let activityID = activityTracker.begin(
                name: name,
                path: url.path,
                kind: .directory
            )
            let listed = directoryChildren(at: url)
            activityTracker.end(id: activityID)
            return listed
        }

        if contents == nil {
            let size = await directoryContentSize(
                at: url,
                label: name,
                path: url.path,
                kind: .enumerate,
                tracker: tracker,
                activityTracker: activityTracker,
                inodeRegistry: inodeRegistry
            )
            tracker.advance(1, item: name)
            let placeholder = DiskNode(
                url: url,
                name: "🔒 Содержимое",
                size: size,
                isDirectory: false,
                colorIndex: colorIndex
            )
            return DiskNode(
                url: url,
                name: inaccessibleName(name),
                size: size,
                children: size > 0 ? [placeholder] : [],
                isDirectory: true,
                colorIndex: colorIndex
            )
        }

        enum ChildWork: Sendable {
            case recurse
            case enumerate
            case file(Int64)
        }

        struct ChildJob: Sendable {
            let index: Int
            let url: URL
            let name: String
            let colorIndex: Int
            let work: ChildWork
        }

        var jobs: [ChildJob] = []
        jobs.reserveCapacity(contents!.count)

        for (index, childURL) in contents!.enumerated() {
            if Task.isCancelled { break }

            let childName = childURL.lastPathComponent
            let childColorIndex = depth == 0 ? ColorPalette.colorIndex(for: index) : colorIndex
            let values = try? childURL.resourceValues(forKeys: resourceKeys)
            let isSymlink = values?.isSymbolicLink == true
            let isDir = !isSymlink && values?.isDirectory == true
            let isPackage = !isSymlink && values?.isPackage == true

            let work: ChildWork
            if isSymlink {
                work = .file(fileSize(at: childURL, values: values, inodeRegistry: inodeRegistry))
            } else if (isDir || isPackage), depth < maxTreeDepth {
                work = .recurse
            } else if isDir || isPackage {
                work = .enumerate
            } else {
                work = .file(fileSize(at: childURL, values: values, inodeRegistry: inodeRegistry))
            }

            jobs.append(ChildJob(
                index: index,
                url: childURL,
                name: childName,
                colorIndex: childColorIndex,
                work: work
            ))
        }

        var indexedChildren: [(Int, DiskNode)] = []
        indexedChildren.reserveCapacity(jobs.count)

        await withTaskGroup(of: (Int, DiskNode)?.self) { group in
            for job in jobs {
                switch job.work {
                case .file(let size):
                    tracker.advance(1, item: job.name)
                    indexedChildren.append((
                        job.index,
                        DiskNode(
                            url: job.url,
                            name: job.name,
                            size: size,
                            isDirectory: false,
                            colorIndex: job.colorIndex
                        )
                    ))

                case .enumerate:
                    group.addTask {
                        if Task.isCancelled { return nil }

                        let deferral = await self.evaluateDeferredScan(at: job.url)
                        if deferral.shouldDefer {
                            tracker.advance(1, item: job.name)
                            return (
                                job.index,
                                DiskNode(
                                    url: job.url,
                                    name: job.name,
                                    size: deferral.estimatedSize,
                                    children: [],
                                    isDirectory: true,
                                    colorIndex: job.colorIndex,
                                    needsLazyScan: true
                                )
                            )
                        }

                        let activityID = activityTracker.begin(
                            name: job.name,
                            path: job.url.path,
                            kind: .enumerate
                        )
                        defer { activityTracker.end(id: activityID) }

                        tracker.report(currentItem: job.name)
                        let size = await self.directoryContentSize(
                            at: job.url,
                            label: job.name,
                            path: job.url.path,
                            kind: .enumerate,
                            tracker: tracker,
                            activityTracker: activityTracker,
                            inodeRegistry: inodeRegistry,
                            activityID: activityID
                        )
                        return (
                            job.index,
                            DiskNode(
                                url: job.url,
                                name: job.name,
                                size: size,
                                children: [],
                                isDirectory: true,
                                colorIndex: job.colorIndex
                            )
                        )
                    }

                case .recurse:
                    group.addTask {
                        if Task.isCancelled { return nil }

                        if depth >= 2 {
                            let deferral = await self.evaluateDeferredScan(at: job.url)
                            if deferral.shouldDefer {
                                tracker.advance(1, item: job.name)
                                return (
                                    job.index,
                                    DiskNode(
                                        url: job.url,
                                        name: job.name,
                                        size: deferral.estimatedSize,
                                        children: [],
                                        isDirectory: true,
                                        colorIndex: job.colorIndex,
                                        needsLazyScan: true
                                    )
                                )
                            }
                        }

                        let activityID = activityTracker.begin(
                            name: job.name,
                            path: job.url.path,
                            kind: .recurse
                        )
                        defer { activityTracker.end(id: activityID) }

                        tracker.report(currentItem: job.name)
                        let childInProgress = depth == 0
                            ? InProgressTopLevel(coordinator: rootPreview)
                            : inProgressTopLevel

                        do {
                            let child = try await self.scanDirectory(
                                url: job.url,
                                name: job.name,
                                depth: depth + 1,
                                colorIndex: job.colorIndex,
                                tracker: tracker,
                                activityTracker: activityTracker,
                                inodeRegistry: inodeRegistry,
                                partialEmitter: partialEmitter,
                                rootPreview: rootPreview,
                                inProgressTopLevel: childInProgress
                            )
                            if depth == 0 {
                                rootPreview?.completeTopLevelChild(child)
                            }
                            return (job.index, child)
                        } catch {
                            if Task.isCancelled { return nil }
                            let size = await self.directoryContentSize(
                                at: job.url,
                                label: job.name,
                                path: job.url.path,
                                kind: .enumerate,
                                tracker: tracker,
                                activityTracker: activityTracker,
                                inodeRegistry: inodeRegistry,
                                activityID: activityID
                            )
                            return (
                                job.index,
                                DiskNode(
                                    url: job.url,
                                    name: self.inaccessibleName(job.name),
                                    size: size,
                                    children: size > 0
                                        ? [DiskNode(
                                            url: job.url,
                                            name: "🔒 Содержимое",
                                            size: size,
                                            isDirectory: false,
                                            colorIndex: job.colorIndex
                                        )]
                                        : [],
                                    isDirectory: true,
                                    colorIndex: job.colorIndex
                                )
                            )
                        }
                    }
                }
            }

            for await result in group {
                if let result {
                    indexedChildren.append(result)
                    if depth == 1 {
                        let partialChildren = indexedChildren
                            .sorted { $0.0 < $1.0 }
                            .map(\.1)
                        let partialSize = partialChildren.reduce(Int64(0)) { $0 + $1.size }
                        reportInProgressTopLevel(
                            depth: depth,
                            inProgressTopLevel: inProgressTopLevel,
                            url: url,
                            name: name,
                            colorIndex: colorIndex,
                            totalSize: partialSize,
                            children: partialChildren
                        )
                    }
                }
            }
        }

        indexedChildren.sort { $0.0 < $1.0 }
        var children = indexedChildren.map(\.1)
        var totalSize = children.reduce(Int64(0)) { $0 + $1.size }
        totalSize = await reconcileDirectorySize(
            url: url,
            children: children,
            listedTotal: totalSize,
            activityTracker: activityTracker,
            inodeRegistry: inodeRegistry
        )

        children.sort { $0.size > $1.size }

        if depth >= 1 {
            children = collapseSmallChildren(children)
            totalSize = children.reduce(Int64(0)) { $0 + $1.size }
        }

        tracker.advance(1, item: name)
        reportInProgressTopLevel(
            depth: depth,
            inProgressTopLevel: inProgressTopLevel,
            url: url,
            name: name,
            colorIndex: colorIndex,
            totalSize: totalSize,
            children: children
        )
        if depth == 0 {
            rootPreview?.publishRootSnapshot(
                children: children,
                totalSize: totalSize,
                force: true
            )
        } else {
            emitPartialRoot(
                depth: depth,
                url: url,
                name: name,
                colorIndex: colorIndex,
                totalSize: totalSize,
                children: children,
                emitter: partialEmitter,
                force: true
            )
        }

        return DiskNode(
            url: url,
            name: name,
            size: max(totalSize, 0),
            children: children,
            isDirectory: true,
            colorIndex: colorIndex
        )
    }

    private func directoryContents(at url: URL) -> [URL]? {
        try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )
    }

    /// Если `contentsOfDirectory` недоступен, пробуем перечислить только верхний уровень.
    private func directoryChildren(at url: URL) -> [URL]? {
        if let listed = directoryContents(at: url), !listed.isEmpty {
            return listed
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsSubdirectoryDescendants]
        ) else {
            return directoryContents(at: url)
        }

        var children: [URL] = []
        for case let item as URL in enumerator {
            children.append(item)
        }
        return children.isEmpty ? directoryContents(at: url) : children
    }

    private func reconcileDirectorySize(
        url: URL,
        children: [DiskNode],
        listedTotal: Int64,
        activityTracker: ScanActivityTracker,
        inodeRegistry: ScanInodeRegistry
    ) async -> Int64 {
        guard children.isEmpty else { return listedTotal }

        let enumerated = await directoryContentSize(
            at: url,
            label: url.lastPathComponent,
            path: url.path,
            kind: .enumerate,
            tracker: WeightedProgressTracker(totalUnits: 1, cache: nil, onProgress: nil),
            activityTracker: activityTracker,
            inodeRegistry: inodeRegistry
        )
        return max(listedTotal, enumerated)
    }

    private func directoryContentSize(
        at url: URL,
        label: String,
        path: String,
        kind: ScanWorkerKind,
        tracker: WeightedProgressTracker,
        activityTracker: ScanActivityTracker,
        inodeRegistry: ScanInodeRegistry,
        activityID: UInt64? = nil
    ) async -> Int64 {
        let ownsActivity = activityID == nil
        let resolvedActivityID = activityID ?? activityTracker.begin(
            name: label,
            path: path,
            kind: kind
        )
        defer {
            if ownsActivity {
                activityTracker.end(id: resolvedActivityID)
            }
        }

        return await concurrencyLimiter.withPermitSync {
            var total: Int64 = 0
            var processedFiles = 0
            var reportedAdvance = 0

            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            ) else {
                tracker.advance(1, item: label)
                return fileSize(at: url, inodeRegistry: inodeRegistry)
            }

            for case let itemURL as URL in enumerator {
                if Task.isCancelled { break }

                guard let values = try? itemURL.resourceValues(forKeys: resourceKeys),
                      values.isSymbolicLink != true,
                      values.isDirectory != true
                else { continue }

                total += fileSize(at: itemURL, values: values, inodeRegistry: inodeRegistry)
                processedFiles += 1

                if processedFiles - reportedAdvance >= 25 {
                    let batch = processedFiles - reportedAdvance
                    let itemLabel = "\(label) (\(processedFiles) файлов)"
                    tracker.advance(batch, item: itemLabel)
                    activityTracker.update(id: resolvedActivityID, name: itemLabel)
                    reportedAdvance = processedFiles
                }
            }

            let remaining = processedFiles - reportedAdvance
            if remaining > 0 {
                tracker.advance(remaining, item: label)
            } else if processedFiles == 0 {
                tracker.advance(1, item: label)
            }

            return max(total, 0)
        }
    }

    private func reportInProgressTopLevel(
        depth: Int,
        inProgressTopLevel: InProgressTopLevel?,
        url: URL,
        name: String,
        colorIndex: Int,
        totalSize: Int64,
        children: [DiskNode]
    ) {
        guard depth == 1 else { return }

        inProgressTopLevel?.update(
            DiskNode(
                url: url,
                name: name,
                size: max(totalSize, 0),
                children: children,
                isDirectory: true,
                colorIndex: colorIndex
            )
        )
    }

    private func fileSize(
        at url: URL,
        values: URLResourceValues? = nil,
        inodeRegistry: ScanInodeRegistry
    ) -> Int64 {
        let credited = inodeRegistry.creditedSize(at: url, values: values)
        guard credited > 0 else { return 0 }
        return max(credited, minimumDisplaySize)
    }

    private func rootWithUniqueSize(_ root: DiskNode, inodeRegistry: ScanInodeRegistry) -> DiskNode {
        let uniqueTotal = inodeRegistry.uniqueTotalBytes
        let hierarchicalTotal = root.children.reduce(Int64(0)) { $0 + $1.size }
        let displaySize: Int64
        if uniqueTotal > 0 {
            displaySize = max(uniqueTotal, hierarchicalTotal)
        } else {
            displaySize = max(root.size, hierarchicalTotal)
        }

        return DiskNode(
            url: root.url,
            name: root.name,
            size: displaySize,
            children: root.children,
            isDirectory: root.isDirectory,
            colorIndex: root.colorIndex
        )
    }

    private func inaccessibleName(_ name: String) -> String {
        "🔒 \(name)"
    }

    private struct DeferredScanEvaluation {
        let shouldDefer: Bool
        let estimatedSize: Int64
    }

    private func evaluateDeferredScan(at url: URL) async -> DeferredScanEvaluation {
        guard let children = directoryChildren(at: url) else {
            return DeferredScanEvaluation(shouldDefer: false, estimatedSize: 0)
        }

        var hasSubdirs = false
        for childURL in children {
            let values = try? childURL.resourceValues(forKeys: resourceKeys)
            let isSymlink = values?.isSymbolicLink == true
            let isDir = !isSymlink && values?.isDirectory == true
            let isPackage = !isSymlink && values?.isPackage == true
            if isDir || isPackage {
                hasSubdirs = true
                break
            }
        }

        let shouldMeasure = hasSubdirs || children.count > 120
        guard shouldMeasure else {
            return DeferredScanEvaluation(shouldDefer: false, estimatedSize: 0)
        }

        let measurement = await directorySizeBelowCap(at: url, cap: deferScanThreshold)

        if measurement.exceedsCap {
            return DeferredScanEvaluation(shouldDefer: false, estimatedSize: 0)
        }

        return DeferredScanEvaluation(
            shouldDefer: true,
            estimatedSize: max(measurement.size, minimumDisplaySize)
        )
    }

    private func logicalFileSize(from values: URLResourceValues?) -> Int64 {
        if let allocated = values?.totalFileAllocatedSize {
            return Int64(allocated)
        }
        if let size = values?.fileSize {
            return Int64(size)
        }
        return 0
    }

    private func directorySizeBelowCap(
        at url: URL,
        cap: Int64
    ) async -> (size: Int64, exceedsCap: Bool) {
        await concurrencyLimiter.withPermitSync {
            var total: Int64 = 0

            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            ) else {
                let values = try? url.resourceValues(forKeys: resourceKeys)
                let size = logicalFileSize(from: values)
                return (size, size >= cap)
            }

            for case let itemURL as URL in enumerator {
                if Task.isCancelled { break }

                guard let values = try? itemURL.resourceValues(forKeys: resourceKeys),
                      values.isSymbolicLink != true,
                      values.isDirectory != true
                else { continue }

                total += logicalFileSize(from: values)
                if total >= cap {
                    return (total, true)
                }
            }

            return (max(total, 0), false)
        }
    }

    private func collapseSmallChildren(_ children: [DiskNode]) -> [DiskNode] {
        guard children.count > 12 else { return children }

        let threshold = children.reduce(Int64(0)) { $0 + $1.size } / 50
        var kept: [DiskNode] = []
        var otherSize: Int64 = 0
        var otherCount = 0

        for child in children {
            if child.needsLazyScan || child.size >= threshold || kept.count < 8 {
                kept.append(child)
            } else {
                otherSize += child.size
                otherCount += 1
            }
        }

        if otherCount > 0 {
            kept.append(DiskNode(
                url: URL(fileURLWithPath: "/"),
                name: "Мелкие объекты (\(otherCount))",
                size: otherSize,
                children: [],
                isDirectory: false,
                colorIndex: 7
            ))
        }

        return kept.sorted { $0.size > $1.size }
    }

    private func emitPartialRoot(
        depth: Int,
        url: URL,
        name: String,
        colorIndex: Int,
        totalSize: Int64,
        children: [DiskNode],
        emitter: PartialRootEmitter,
        force: Bool = false
    ) {
        guard depth == 0 else { return }
        emitter.emit(
            DiskNode(
                url: url,
                name: name,
                size: max(totalSize, 0),
                children: force ? children.sorted { $0.size > $1.size } : children,
                isDirectory: true,
                colorIndex: colorIndex
            ),
            force: force
        )
    }

    enum ScanError: LocalizedError {
        case pathNotFound(URL)

        var errorDescription: String? {
            switch self {
            case .pathNotFound(let url):
                "Путь не найден: \(url.path)"
            }
        }
    }
}

private actor ScanConcurrencyLimiter {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) {
        self.permits = max(permits, 1)
    }

    func withPermit<T>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    func withPermitSync<T>(_ operation: @Sendable () -> T) async -> T {
        await acquire()
        let result = operation()
        release()
        return result
    }

    private func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if let continuation = waiters.first {
            waiters.removeFirst()
            continuation.resume()
        } else {
            permits += 1
        }
    }
}

private final class RootPreviewCoordinator: @unchecked Sendable {
    private let rootURL: URL
    private let rootName: String
    private let rootColorIndex: Int
    private let previewRootID: UUID
    private let emitter: PartialRootEmitter
    private let lock = NSLock()
    private var completedChildren: [DiskNode] = []

    init(
        url: URL,
        name: String,
        colorIndex: Int,
        previewRootID: UUID,
        emitter: PartialRootEmitter
    ) {
        self.rootURL = url
        self.rootName = name
        self.rootColorIndex = colorIndex
        self.previewRootID = previewRootID
        self.emitter = emitter
    }

    func completeTopLevelChild(_ child: DiskNode) {
        lock.lock()
        completedChildren.append(child)
        lock.unlock()
        emit(inProgress: nil, force: true)
    }

    func updateInProgressTopLevel(_ child: DiskNode) {
        emit(inProgress: child)
    }

    func publishRootSnapshot(children: [DiskNode], totalSize: Int64, force: Bool = false) {
        lock.lock()
        completedChildren = children
        lock.unlock()
        publish(children: children.sorted { $0.size > $1.size }, force: force)
    }

    private func emit(inProgress: DiskNode?, force: Bool = false) {
        lock.lock()
        var children = completedChildren
        lock.unlock()

        if let inProgress {
            children.append(inProgress)
        }

        let sortedChildren = children.sorted { $0.size > $1.size }
        let displaySize = sortedChildren.reduce(Int64(0)) { $0 + $1.size }

        emitter.emit(
            DiskNode(
                id: previewRootID,
                url: rootURL,
                name: rootName,
                size: displaySize,
                children: sortedChildren,
                isDirectory: true,
                colorIndex: rootColorIndex
            ),
            force: force
        )
    }

    private func publish(children: [DiskNode], force: Bool) {
        let displaySize = children.reduce(Int64(0)) { $0 + $1.size }
        emitter.emit(
            DiskNode(
                id: previewRootID,
                url: rootURL,
                name: rootName,
                size: displaySize,
                children: children,
                isDirectory: true,
                colorIndex: rootColorIndex
            ),
            force: force
        )
    }
}

private final class InProgressTopLevel: @unchecked Sendable {
    private let coordinator: RootPreviewCoordinator?
    private let lock = NSLock()
    private var lastEmit = Date.distantPast
    private let minInterval: TimeInterval = 0.15

    init(coordinator: RootPreviewCoordinator?) {
        self.coordinator = coordinator
    }

    func update(_ partial: DiskNode) {
        guard let coordinator else { return }
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= minInterval else {
            lock.unlock()
            return
        }
        lastEmit = now
        lock.unlock()
        coordinator.updateInProgressTopLevel(partial)
    }
}

private final class PartialRootEmitter: @unchecked Sendable {
    private let handler: (@Sendable (DiskNode) -> Void)?
    private let lock = NSLock()
    private var lastEmit = Date.distantPast
    private let minInterval: TimeInterval = 0.12

    init(handler: (@Sendable (DiskNode) -> Void)?) {
        self.handler = handler
    }

    func emit(_ node: DiskNode, force: Bool = false) {
        guard let handler else { return }
        lock.lock()
        let now = Date()
        guard force || now.timeIntervalSince(lastEmit) >= minInterval else {
            lock.unlock()
            return
        }
        lastEmit = now
        lock.unlock()
        handler(node)
    }
}

private final class WeightedProgressTracker: @unchecked Sendable {
    private let onProgress: (@Sendable (ScanProgress) -> Void)?
    private let totalUnits: Int
    private let cache: ScanTreeCacheEntry?
    private let usesDynamicTotal: Bool
    private let volumeUsedTarget: Int64?
    private let lock = NSLock()
    private var estimatedTotal: Int
    private var completedUnits = 0
    private var discoveredBytes: Int64 = 0
    private var currentItem = ""

    init(
        totalUnits: Int,
        cache: ScanTreeCacheEntry?,
        usesDynamicTotal: Bool = false,
        volumeUsedTarget: Int64? = nil,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) {
        self.totalUnits = max(totalUnits, 1)
        self.cache = cache
        self.usesDynamicTotal = usesDynamicTotal
        self.volumeUsedTarget = volumeUsedTarget
        self.estimatedTotal = max(totalUnits, 1)
        self.onProgress = onProgress
    }

    func setDiscoveredBytes(_ bytes: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        discoveredBytes = max(discoveredBytes, bytes)
        lock.unlock()
        publish()
    }

    func units(for path: String, fallback: Int) -> Int {
        guard let cache else { return fallback }
        return ScanTreeCache.workUnits(for: path, in: cache) ?? fallback
    }

    func report(currentItem: String) {
        lock.lock()
        self.currentItem = currentItem
        lock.unlock()
        publish()
    }

    func advance(_ units: Int, item: String) {
        lock.lock()
        currentItem = item
        completedUnits += max(units, 0)
        lock.unlock()
        publish()
    }

    func advance(path: String, fallback: Int, item: String) {
        advance(units(for: path, fallback: fallback), item: item)
    }

    func complete() {
        lock.lock()
        completedUnits = max(completedUnits, effectiveTotalLocked())
        let effectiveTotal = max(effectiveTotalLocked(), completedUnits)
        let item = currentItem
        lock.unlock()

        onProgress?(ScanProgress(
            currentItem: item,
            completed: effectiveTotal,
            total: effectiveTotal,
            phase: .scanning,
            isComplete: true,
            discoveredBytes: discoveredBytes,
            volumeUsedTarget: volumeUsedTarget
        ))
    }

    private func effectiveTotalLocked() -> Int {
        if usesDynamicTotal {
            if completedUnits >= estimatedTotal * 6 / 10 {
                estimatedTotal = max(
                    estimatedTotal,
                    completedUnits + max(completedUnits / 2, 1_000)
                )
            }
            return max(estimatedTotal, completedUnits + max(completedUnits / 20, 50), 1)
        }
        return max(totalUnits, completedUnits, 1)
    }

    private func publish() {
        lock.lock()
        let effectiveTotal = effectiveTotalLocked()
        let completed = min(completedUnits, effectiveTotal)
        let item = currentItem
        let bytes = discoveredBytes
        let target = volumeUsedTarget
        lock.unlock()

        onProgress?(ScanProgress(
            currentItem: item,
            completed: completed,
            total: effectiveTotal,
            phase: .scanning,
            isComplete: false,
            discoveredBytes: bytes > 0 ? bytes : nil,
            volumeUsedTarget: target
        ))
    }
}
