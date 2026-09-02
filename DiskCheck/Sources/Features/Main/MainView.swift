import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var store: DiskScanStore
    @Bindable var trashStore: TrashStore
    @State private var showsScanSetup = true
    @State private var sidebarWidth = SidebarWidthStorage.load()

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if store.needsFullDiskAccess {
                fullDiskAccessBanner
                Divider()
            }

            if let health = store.volumeHealth, health.hasUnhealthySmart {
                DiskHealthBanner(health: health)
                Divider()
            }

            Group {
                if store.isScanning {
                    scanningView
                } else if showsScanSetup {
                    emptyStateView
                } else if let node = store.currentNode {
                    contentView(node: node)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshFullDiskAccessStatus()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if store.isScanning {
                Button("Остановить", role: .destructive) {
                    stopScanAndShowSetup()
                }
            } else if !showsScanSetup {
                Button("Сканировать") {
                    store.returnToScanSetup()
                    showsScanSetup = true
                }
            }

            Spacer()

            if store.root != nil, !store.isScanning, !showsScanSetup {
                Picker("", selection: $store.browseMode) {
                    ForEach(BrowseMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.hasFullDiskAccess ? "Сканировано не полностью" : "Неполный доступ к диску")
                    .font(.subheadline.weight(.semibold))
                Text(fullDiskAccessBannerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !store.hasFullDiskAccess {
                Button("Открыть настройки") {
                    store.openFullDiskAccessSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }

    private var fullDiskAccessBannerMessage: String {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DiskCheck"
        let inaccessible = ByteFormatter.format(store.inaccessibleScannedSize)

        if store.inaccessibleScannedSize > 0 {
            if store.hasFullDiskAccess {
                return "Недоступно \(inaccessible) — часть системных папок не читается (это нормально для macOS)."
            }
            return "Недоступно \(inaccessible). Разрешите доступ к папкам при запросе системы или включите «Полный доступ к диску» для \(appName), перезапустите и отсканируйте снова."
        }

        return "Сканирование не охватило весь диск. Разрешите доступ к папкам при запросе системы или включите «Полный доступ к диску» для \(appName)."
    }

    @ViewBuilder
    private func contentView(node: DiskNode) -> some View {
        HSplitView {
            sunburstColumn(node: node)
            sidebarColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sunburstColumn(node: DiskNode) -> some View {
        VStack(spacing: 12) {
            visualizationView(node: node)
                .id(node.id)

            Spacer(minLength: 0)

            TrashBinView(trashStore: trashStore) {
                await finishTrashOperation()
            }
        }
        .padding(16)
        .frame(minWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        if let legendNode = store.currentNode {
            VStack(spacing: 0) {
                Group {
                    switch store.browseMode {
                    case .tree:
                        LegendView(
                            node: legendNode,
                            breadcrumbItems: store.breadcrumbItems,
                            canGoBack: store.canNavigateUp,
                            totalCapacity: store.totalCapacity,
                            availableSpace: store.availableSpace,
                            rootScannedSize: store.root.map {
                                DiskNodeTrash.displaySize(for: $0, trashedPaths: trashStore.trashedPaths)
                            } ?? 0,
                            isAtScanRoot: store.navigationPath.isEmpty,
                            trashedPaths: trashStore.trashedPaths,
                            expandingLazyScanPath: store.expandingLazyScanPath,
                            onBack: { store.navigateUp() },
                            onNavigateTo: { store.navigateTo(index: $0) },
                            onSelect: { store.drillDown(to: $0) },
                            onStage: { trashStore.add($0) }
                        )
                    case .categories:
                        CategoriesView(
                            categoryIndex: store.categoryIndex,
                            trashedPaths: trashStore.trashedPaths,
                            onStage: { trashStore.add($0) },
                            onShowInTree: { store.revealInTree($0) }
                        )
                    case .aiAdvice:
                        AIAdviceView(
                            advice: store.aiAdvice,
                            state: store.aiAdviceState,
                            extendedAdvice: store.aiExtendedAdvice,
                            extendedState: store.aiExtendedAdviceState,
                            canRequestExtended: store.canRequestExtendedAIAdvice,
                            backendName: store.aiBackendName,
                            trashedPaths: trashStore.trashedPaths,
                            onRefresh: { store.refreshAIAdvice() },
                            onRequestExtended: { store.requestExtendedAIAdvice() },
                            onRefreshExtended: { store.refreshExtendedAIAdvice() },
                            onStage: { trashStore.add($0) },
                            onShowInTree: { store.revealInTree($0) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.volumeHealth != nil || store.iCloudSummary != nil {
                    Divider()
                    VolumeInsightsView(
                        health: store.volumeHealth,
                        iCloudSummary: store.iCloudSummary
                    )
                }
            }
            .frame(
                minWidth: SidebarWidthStorage.minimumWidth,
                idealWidth: sidebarWidth,
                maxHeight: .infinity
            )
            .trackSidebarWidth($sidebarWidth)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func visualizationView(node: DiskNode) -> some View {
        SunburstView(
            node: node,
            trashStore: trashStore,
            onSelect: { store.drillDown(to: $0) },
            onCenterTap: { store.navigateUp() },
            onStage: { trashStore.add($0) }
        )
    }

    private func stopScanAndShowSetup() {
        store.returnToScanSetup()
        showsScanSetup = true
    }

    private func finishTrashOperation() async {
        guard let operation = trashStore.pendingOperation else { return }
        let errors = await trashStore.execute(operation)
        if let firstError = errors.first {
            store.errorMessage = firstError
        }
        rescanCurrentLocation()
    }

    private func rescanCurrentLocation() {
        if let focus = store.focusNode {
            store.scan(
                url: focus.url,
                capacity: store.totalCapacity,
                available: store.availableSpace,
                promptForFullDiskAccess: false
            )
        } else if let root = store.root {
            store.scan(
                url: root.url,
                capacity: store.totalCapacity,
                available: store.availableSpace,
                promptForFullDiskAccess: false
            )
        } else {
            store.scanSelectedVolume()
        }
    }

    private var scanningView: some View {
        HSplitView {
            VStack(spacing: 12) {
                Group {
                    if let preview = store.scanningPreviewRoot {
                        SunburstView(
                            node: preview,
                            trashStore: trashStore,
                            isInteractive: false,
                            onSelect: { _ in },
                            onCenterTap: {},
                            onStage: { _ in }
                        )
                        .id(store.scanningPreviewRenderKey)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                    } else {
                        ScanningRingView(
                            fraction: store.scanProgressFraction,
                            title: store.scanPhase == .estimating ? "Подсчёт объектов…" : "Сканирование",
                            subtitle: store.scanProgress,
                            isIndeterminate: store.scanPhase == .estimating
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(minWidth: 420)
            .frame(maxHeight: .infinity, alignment: .top)

            scanningStatusPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningStatusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Сканирование")
                    .font(.title3.weight(.semibold))

                Text(store.scanPhase == .estimating ? "Подготовка оценки объёма работы" : "Собираем карту диска")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Прогресс")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(store.scanProgressFraction * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: store.scanProgressFraction, total: 1)
                    .progressViewStyle(.linear)

                if store.scanVolumeUsedTarget > 0 {
                    HStack {
                        Text("Найдено данных")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(ByteFormatter.format(store.scanDiscoveredBytes)) из \(ByteFormatter.format(store.scanVolumeUsedTarget))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let preview = store.scanningPreviewRoot, store.scanPhase == .scanning {
                    HStack {
                        Text("Готово папок верхнего уровня")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(preview.children.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Уже найдено")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(preview.size > 0 ? ByteFormatter.format(preview.size) : "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .opacity(preview.size > 0 ? 1 : 0.35)
                }
            }

            Divider()

            if store.scanPhase == .scanning {
                ScanThreadsChartView(activity: store.scanActivity)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Сейчас")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(store.scanProgress.isEmpty ? "…" : store.scanProgress)
                    .font(.body)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 240, idealWidth: 280, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyStateView: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    Text("DiskCheck")
                        .font(.largeTitle.weight(.bold))

                    Text("Анализ дискового пространства с кластеризацией\nв стиле DaisyDisk")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    Picker("Том", selection: $store.selectedVolume) {
                        ForEach(store.volumes) { volume in
                            Text(volume.name).tag(Optional(volume))
                        }
                    }
                    .frame(maxWidth: 280)

                    HStack(spacing: 12) {
                        Button("Сканировать диск") {
                            trashStore.clear()
                            store.scanSelectedVolume()
                            if store.isScanning {
                                showsScanSetup = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(store.selectedVolume == nil)

                        Button("Выбрать папку") {
                            trashStore.clear()
                            store.pickFolder()
                            if store.isScanning {
                                showsScanSetup = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Text("Перетаскивайте сюда файлы и папки")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TrashBinView(trashStore: trashStore) {
                await finishTrashOperation()
            }
            .frame(maxWidth: 420)
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            Task { @MainActor in
                trashStore.clear()
                store.scanUserSelectedFolder(url)
                if store.isScanning {
                    showsScanSetup = false
                }
            }
        }
        return true
    }
}
