import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class DiskScanStore {
    var root: DiskNode?
    var focusNode: DiskNode?
    var navigationPath: [DiskNode] = []
    var totalCapacity: Int64 = 0
    var availableSpace: Int64 = 0
    var volumes: [VolumeInfo] = []
    var selectedVolume: VolumeInfo?
    var isScanning = false
    var scanningTargetName: String?
    var scanProgress: String = ""
    var scanProgressFraction: Double = 0
    var scanPhase: ScanPhase = .scanning
    var scanningPreviewRoot: DiskNode?
    var scanActivity: ScanActivitySnapshot = .empty
    var errorMessage: String?
    var needsFullDiskAccess = false
    var hasFullDiskAccess = FullDiskAccessChecker.isGranted
    var browseMode: BrowseMode = BrowseModeStorage.load() {
        didSet {
            let mode = browseMode
            Task.detached(priority: .utility) {
                BrowseModeStorage.save(mode)
            }
        }
    }
    var categoryIndex: CategoryIndex = .empty
    var aiAdvice: AIDeletionAdvice?
    var aiAdviceState: AIAdviceState = .idle
    var aiExtendedAdvice: AIDeletionAdvice?
    var aiExtendedAdviceState: AIAdviceState = .idle
    var aiBackendName: String?
    var canRequestExtendedAIAdvice = false
    var volumeHealth: VolumeHealthReport?
    var iCloudSummary: ICloudStorageSummary?
    var scanDiscoveredBytes: Int64 = 0
    var scanVolumeUsedTarget: Int64 = 0

    private var aiOverviewPaths: Set<String> = []
    private var skippedFullDiskAccessPromptThisSession = false

    func refreshFullDiskAccessStatus() {
        FullDiskAccessChecker.refreshAssumptions()
        hasFullDiskAccess = FullDiskAccessChecker.isGranted
        if FullDiskAccessChecker.maySkipPrompt {
            skippedFullDiskAccessPromptThisSession = true
        }
    }

    private let scanner = DiskScanner()
    private var scanTask: Task<Void, Never>?
    private var lazyScanTask: Task<Void, Never>?
    var expandingLazyScanPath: String?

    private var aiAdviceTask: Task<Void, Never>?
    private var aiExtendedAdviceTask: Task<Void, Never>?
    private var securityScopedURL: URL?

    init() {
        FullDiskAccessStorage.migrateIfNeeded()
        volumes = VolumeInfoProvider.availableVolumes()
        selectedVolume = volumes.first { $0.url.path == "/System/Volumes/Data" }
            ?? volumes.first
    }

    var currentNode: DiskNode? {
        focusNode ?? root
    }

    var usedSpace: Int64 {
        max(0, totalCapacity - availableSpace)
    }

    var unscannedSpace: Int64 {
        guard let root else { return 0 }
        return max(0, usedSpace - root.size)
    }

    var inaccessibleScannedSize: Int64 {
        guard let root else { return 0 }
        return DiskNodeAccessMetrics.inaccessibleSize(in: root)
    }

    var breadcrumbItems: [DiskNode] {
        if let root {
            return [root] + navigationPath
        }
        return navigationPath
    }

    var canNavigateUp: Bool {
        !navigationPath.isEmpty
    }

    var scanningPreviewRenderKey: String {
        guard let preview = scanningPreviewRoot else { return "empty" }
        let childSignature = preview.sortedChildren.map {
            "\($0.id.uuidString):\($0.size):\($0.children.count)"
        }.joined(separator: "|")
        return "\(preview.size)|\(childSignature)"
    }

    func scanSelectedVolume() {
        guard let volume = selectedVolume else { return }
        scan(url: volume.url, capacity: volume.totalCapacity, available: volume.availableSpace)
    }

    func returnToScanSetup() {
        scanTask?.cancel()
        lazyScanTask?.cancel()
        aiAdviceTask?.cancel()
        aiExtendedAdviceTask?.cancel()
        isScanning = false
        scanningTargetName = nil
        scanProgress = ""
        scanProgressFraction = 0
        scanPhase = .scanning
        scanActivity = .empty
        scanningPreviewRoot = nil
        expandingLazyScanPath = nil
        root = nil
        focusNode = nil
        navigationPath = []
        categoryIndex = .empty
        aiAdvice = nil
        aiAdviceState = .idle
        aiExtendedAdvice = nil
        aiExtendedAdviceState = .idle
        aiBackendName = nil
        canRequestExtendedAIAdvice = false
        volumeHealth = nil
        iCloudSummary = nil
        scanDiscoveredBytes = 0
        scanVolumeUsedTarget = 0
        aiOverviewPaths = []
        errorMessage = nil
        needsFullDiskAccess = false
        DiskNodeTrashCache.invalidateTree()
        releaseSecurityScopedAccess()
    }

    func scan(
        url: URL,
        capacity: Int64? = nil,
        available: Int64? = nil,
        promptForFullDiskAccess: Bool = true
    ) {
        hasFullDiskAccess = FullDiskAccessChecker.isGranted

        if promptForFullDiskAccess, !ensureFullDiskAccessBeforeScan() {
            return
        }

        let scanURL = VolumeInfoProvider.scanningURL(for: url)

        scanTask?.cancel()
        lazyScanTask?.cancel()
        expandingLazyScanPath = nil
        releaseSecurityScopedAccess()
        isScanning = true
        scanningTargetName = scanDisplayName(for: scanURL)
        errorMessage = nil
        needsFullDiskAccess = false
        scanProgress = "Подготовка к сканированию…"
        scanProgressFraction = 0
        scanPhase = .scanning
        scanActivity = .empty
        scanningPreviewRoot = nil
        root = nil
        focusNode = nil
        navigationPath = []
        categoryIndex = .empty
        aiAdvice = nil
        aiAdviceState = .idle
        aiExtendedAdvice = nil
        aiExtendedAdviceState = .idle
        aiBackendName = nil
        canRequestExtendedAIAdvice = false
        volumeHealth = nil
        iCloudSummary = nil
        scanDiscoveredBytes = 0
        scanVolumeUsedTarget = 0
        aiOverviewPaths = []
        aiAdviceTask?.cancel()
        aiExtendedAdviceTask?.cancel()
        DiskNodeTrashCache.invalidateTree()
        ScanNotificationService.requestAuthorizationIfNeeded()

        if let capacity, let available {
            totalCapacity = capacity
            availableSpace = available
        } else if let values = try? scanURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]) {
            totalCapacity = Int64(values.volumeTotalCapacity ?? 0)
            availableSpace = Int64(values.volumeAvailableCapacity ?? 0)
        } else {
            totalCapacity = capacity ?? 0
            availableSpace = available ?? 0
        }

        scanVolumeUsedTarget = max(1, totalCapacity - availableSpace)
        scanDiscoveredBytes = 0
        volumeHealth = nil
        iCloudSummary = nil

        ProtectedFolderAccess.warmUpForVolumeScan(at: scanURL)

        scanningPreviewRoot = DiskNode(
            url: scanURL,
            name: scanDisplayName(for: scanURL),
            size: 0,
            children: [],
            isDirectory: true
        )
        let previewRootID = scanningPreviewRoot!.id
        let volumeUsedTarget = scanVolumeUsedTarget
        let scanURLForDiagnostics = scanURL

        scanTask = Task {
            do {
                let cache = ScanTreeCache.load(rootPath: scanURL.path)
                let node = try await scanner.scan(
                    url: scanURL,
                    cache: cache,
                    previewRootID: previewRootID,
                    volumeUsedTarget: volumeUsedTarget > 0 ? volumeUsedTarget : nil,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self else { return }
                            self.scanPhase = progress.phase
                            self.scanProgressFraction = progress.fraction
                            if let discovered = progress.discoveredBytes {
                                self.scanDiscoveredBytes = discovered
                            }
                            if !progress.currentItem.isEmpty {
                                self.scanProgress = progress.currentItem
                            }
                        }
                    },
                    onPartialRoot: { [weak self] partial in
                        Task { @MainActor in
                            guard let self else { return }
                            self.scanningPreviewRoot = DiskNode(
                                id: previewRootID,
                                url: partial.url,
                                name: partial.name,
                                size: partial.size,
                                children: partial.children,
                                isDirectory: partial.isDirectory,
                                colorIndex: partial.colorIndex,
                                needsLazyScan: partial.needsLazyScan
                            )
                            self.scanDiscoveredBytes = partial.size
                            if self.scanVolumeUsedTarget > 0 {
                                self.scanProgressFraction = min(
                                    0.99,
                                    Double(partial.size) / Double(self.scanVolumeUsedTarget)
                                )
                            }
                        }
                    },
                    onActivity: { [weak self] activity in
                        Task { @MainActor in
                            self?.scanActivity = activity
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                DiskNodeTrashCache.invalidateTree()
                root = node
                scanningPreviewRoot = nil
                focusNode = nil
                navigationPath = []
                let rootSnapshot = node
                let builtIndex = await Task.detached(priority: .userInitiated) { () -> CategoryIndex in
                    DiskCategoryClassifier.buildIndex(root: rootSnapshot)
                }.value
                guard !Task.isCancelled else { return }
                categoryIndex = builtIndex
                await Task.detached(priority: .utility) {
                    ScanTreeCache.save(ScanWorkEstimator.buildCache(root: rootSnapshot))
                }.value
                updateAccessWarning(root: node)
                scanProgressFraction = 1
                scanDiscoveredBytes = node.size
                isScanning = false
                scanningTargetName = nil
                scanProgress = ""
                scanActivity = .empty
                await ScanNotificationService.notifyScanCompleted(
                    volumeName: node.name,
                    totalSize: node.size
                )
                loadVolumeInsights(for: scanURLForDiagnostics, root: node, index: builtIndex)
                requestAIAdviceIfAvailable(for: node)
                releaseSecurityScopedAccess()
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isScanning = false
                scanningTargetName = nil
                scanningPreviewRoot = nil
                scanProgress = ""
                scanProgressFraction = 0
                scanActivity = .empty
                releaseSecurityScopedAccess()
            }
        }
    }

    func scanUserSelectedFolder(_ url: URL) {
        releaseSecurityScopedAccess()
        securityScopedURL = url
        _ = SecurityScopedAccess.begin(url: url)
        scan(url: url, promptForFullDiskAccess: false)
    }

    private func releaseSecurityScopedAccess() {
        if let securityScopedURL {
            SecurityScopedAccess.end(url: securityScopedURL)
            self.securityScopedURL = nil
        }
    }

    private func scanDisplayName(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.isEmpty || name == "/" {
            return selectedVolume?.name ?? "Диск"
        }
        return name
    }

    private func updateAccessWarning(root: DiskNode) {
        let inaccessible = DiskNodeAccessMetrics.inaccessibleSize(in: root)
        let lockedDirectories = DiskNodeAccessMetrics.inaccessibleDirectoryCount(in: root)
        hasFullDiskAccess = FullDiskAccessChecker.isGranted

        let inaccessibleThreshold: Int64 = 268_435_456
        let hasInaccessibleData = lockedDirectories > 0 && inaccessible > inaccessibleThreshold
        needsFullDiskAccess = hasInaccessibleData && !hasFullDiskAccess
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadVolumeInsights(for volumeURL: URL, root: DiskNode, index: CategoryIndex) {
        let initialSummary = ICloudStorageAnalyzer.analyze(root: root, categoryIndex: index)
        iCloudSummary = initialSummary

        Task {
            async let health = VolumeDiagnosticsService.loadReport(for: volumeURL)
            async let enriched = ICloudStorageAnalyzer.enrichWithUbiquityAttributes(initialSummary)
            let loadedHealth = await health
            let loadedSummary = await enriched
            guard !Task.isCancelled else { return }
            volumeHealth = loadedHealth
            iCloudSummary = loadedSummary
        }
    }

    func openDiskUtility() {
        SystemIntegration.openDiskUtility()
    }

    func openTimeMachineSnapshots() {
        SystemIntegration.openTimeMachineSettings()
    }

    @discardableResult
    private func ensureFullDiskAccessBeforeScan() -> Bool {
        refreshFullDiskAccessStatus()
        guard !FullDiskAccessChecker.maySkipPrompt else { return true }

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DiskCheck"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Нужен полный доступ к диску"
        alert.informativeText = """
        Для полного сканирования диска добавьте \(appName) в «Конфиденциальность и безопасность → Полный доступ к диску», \
        перезапустите приложение и нажмите «Доступ уже включён».

        Можно начать сканирование и без доступа — тогда часть системных папок будет недоступна.
        """
        alert.addButton(withTitle: "Сканировать")
        alert.addButton(withTitle: "Доступ уже включён")
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Отмена")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            skippedFullDiskAccessPromptThisSession = true
            FullDiskAccessStorage.setSkippedPrompt(true)
            return true
        case .alertSecondButtonReturn:
            skippedFullDiskAccessPromptThisSession = true
            FullDiskAccessStorage.setSkippedPrompt(true)
            FullDiskAccessStorage.setUserConfirmedGranted(true)
            hasFullDiskAccess = true
            return true
        case .alertThirdButtonReturn:
            openFullDiskAccessSettings()
            return false
        default:
            return false
        }
    }

    func drillDown(to node: DiskNode) {
        guard node.isDirectory else { return }

        if node.needsLazyScan {
            navigationPath.append(node)
            focusNode = node
            expandLazyScan(for: node)
            return
        }

        guard !node.children.isEmpty else { return }
        navigationPath.append(node)
        focusNode = node
    }

    private func expandLazyScan(for node: DiskNode) {
        let targetPath = node.url.standardizedFileURL.path
        lazyScanTask?.cancel()
        expandingLazyScanPath = targetPath

        lazyScanTask = Task {
            do {
                let expanded = try await scanner.scanSubtree(
                    at: node.url,
                    colorIndex: node.colorIndex
                )
                guard !Task.isCancelled else { return }
                guard var tree = root else { return }

                if replaceNode(atPath: targetPath, with: expanded, in: &tree) {
                    root = tree
                    DiskNodeTrashCache.invalidateTree()
                    let treeSnapshot = tree
                    let builtIndex = await Task.detached(priority: .userInitiated) { () -> CategoryIndex in
                        DiskCategoryClassifier.buildIndex(root: treeSnapshot)
                    }.value
                    guard !Task.isCancelled else { return }
                    categoryIndex = builtIndex
                    await Task.detached(priority: .utility) {
                        ScanTreeCache.save(ScanWorkEstimator.buildCache(root: treeSnapshot))
                    }.value
                    refreshFocusedNode(matching: targetPath)
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }

            if expandingLazyScanPath == targetPath {
                expandingLazyScanPath = nil
            }
        }
    }

    private func refreshFocusedNode(matching path: String) {
        guard let root else { return }

        if focusNode?.url.standardizedFileURL.path == path {
            focusNode = findNode(atPath: path, in: root)
        }

        for index in navigationPath.indices {
            if navigationPath[index].url.standardizedFileURL.path == path {
                if let updated = findNode(atPath: path, in: root) {
                    navigationPath[index] = updated
                }
            }
        }
    }

    private func findNode(atPath path: String, in node: DiskNode) -> DiskNode? {
        if node.url.standardizedFileURL.path == path {
            return node
        }
        for child in node.children {
            if let found = findNode(atPath: path, in: child) {
                return found
            }
        }
        return nil
    }

    @discardableResult
    private func replaceNode(atPath path: String, with replacement: DiskNode, in root: inout DiskNode) -> Bool {
        let standardized = path
        if root.url.standardizedFileURL.path == standardized {
            root = DiskNode(
                id: root.id,
                url: replacement.url,
                name: replacement.name,
                size: replacement.size,
                children: replacement.children,
                isDirectory: replacement.isDirectory,
                colorIndex: root.colorIndex,
                needsLazyScan: false
            )
            return true
        }

        for index in root.children.indices {
            if replaceNode(atPath: standardized, with: replacement, in: &root.children[index]) {
                root.size = root.children.reduce(Int64(0)) { $0 + $1.size }
                return true
            }
        }

        return false
    }

    func navigateUp() {
        guard !navigationPath.isEmpty else {
            focusNode = nil
            return
        }
        navigationPath.removeLast()
        focusNode = navigationPath.last
    }

    func navigateToRoot() {
        navigationPath = []
        focusNode = nil
    }

    func navigateTo(index: Int) {
        guard index >= 0, index < breadcrumbItems.count else { return }
        if index == 0 {
            navigateToRoot()
        } else {
            navigationPath = Array(breadcrumbItems.dropFirst().prefix(index))
            focusNode = navigationPath.last
        }
    }

    func revealInTree(_ node: DiskNode) {
        browseMode = .tree
        guard let root else { return }

        var path: [DiskNode] = []
        if findPath(to: node.url, from: root, accumulating: &path) {
            navigationPath = path
            focusNode = path.last
        }
    }

    private func findPath(to url: URL, from node: DiskNode, accumulating path: inout [DiskNode]) -> Bool {
        if node.url.standardizedFileURL == url.standardizedFileURL {
            return true
        }
        guard node.isDirectory else { return false }

        for child in node.children {
            path.append(child)
            if findPath(to: url, from: child, accumulating: &path) {
                return true
            }
            path.removeLast()
        }
        return false
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Выберите папку для анализа"

        if panel.runModal() == .OK, let url = panel.url {
            scanUserSelectedFolder(url)
        }
    }

    func requestAIAdviceIfAvailable(for node: DiskNode? = nil) {
        guard let rootNode = node ?? root else { return }

        aiAdviceTask?.cancel()
        aiAdviceTask = Task {
            let backend = await DeletionAdvisorService.detectBackend()
            guard !Task.isCancelled else { return }

            if let backend {
                aiBackendName = backend.displayName
                aiAdviceState = .loading
            } else {
                aiBackendName = AIAdvisorBackend.rules.displayName
                aiAdvice = RuleBasedAdvisorProvider.suggest(root: rootNode, categoryIndex: categoryIndex)
                aiAdviceState = .ready
                return
            }

            let advice = await DeletionAdvisorService.suggest(
                root: rootNode,
                categoryIndex: categoryIndex,
                scope: .overview,
                backend: backend
            )
            guard !Task.isCancelled else { return }

            let categorySnapshot = categoryIndex
            let overviewSummary = await Task.detached(priority: .userInitiated) {
                ScanTreeSummarizer.summarize(
                    root: rootNode,
                    categoryIndex: categorySnapshot
                )
            }.value
            let overviewPaths = ScanTreeSummarizer.paths(from: overviewSummary)
            aiOverviewPaths = overviewPaths
            let hasRemaining = await Task.detached(priority: .userInitiated) {
                ScanTreeSummarizer.summarizeRemaining(
                    root: rootNode,
                    excludingPaths: overviewPaths,
                    limit: 1
                ).entries.count > 0
            }.value
            canRequestExtendedAIAdvice = backend != nil && hasRemaining

            aiAdvice = advice
            if advice.providerName == AIAdvisorBackend.rules.displayName, backend != nil {
                aiAdviceState = .failed("ИИ не смогла сформировать ответ. Показаны встроенные правила.")
            } else {
                aiAdviceState = .ready
            }
        }
    }

    func requestExtendedAIAdvice() {
        guard let rootNode = root else { return }
        guard canRequestExtendedAIAdvice else { return }

        aiExtendedAdviceTask?.cancel()
        aiExtendedAdviceTask = Task {
            guard let backend = await DeletionAdvisorService.detectBackend() else {
                aiExtendedAdviceState = .unavailable(
                    "ИИ недоступна. Включите Apple Intelligence или запустите Ollama."
                )
                return
            }
            guard !Task.isCancelled else { return }

            aiExtendedAdviceState = .loading

            let advice = await DeletionAdvisorService.suggest(
                root: rootNode,
                categoryIndex: categoryIndex,
                scope: .remainingFiles,
                excludingPaths: aiOverviewPaths,
                backend: backend
            )
            guard !Task.isCancelled else { return }

            aiExtendedAdvice = advice
            if advice.categories.isEmpty {
                aiExtendedAdviceState = .failed("ИИ не нашла дополнительных категорий для очистки.")
            } else {
                aiExtendedAdviceState = .ready
            }
        }
    }

    func refreshAIAdvice() {
        aiExtendedAdvice = nil
        aiExtendedAdviceState = .idle
        requestAIAdviceIfAvailable()
    }

    func refreshExtendedAIAdvice() {
        requestExtendedAIAdvice()
    }
}
