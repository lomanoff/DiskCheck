import Foundation

enum DiskCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case gitRepositories
    case noSync
    case nodeModules
    case xcodeDerivedData
    case buildArtifacts
    case packageManagerCaches
    case appCaches
    case logs
    case ideMetadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gitRepositories: "Git-репозитории"
        case .noSync: ".nosync"
        case .nodeModules: "node_modules"
        case .xcodeDerivedData: "Xcode DerivedData"
        case .buildArtifacts: "Артефакты сборки"
        case .packageManagerCaches: "Кэши пакетных менеджеров"
        case .appCaches: "Кэши приложений"
        case .logs: "Логи"
        case .ideMetadata: "Метаданные IDE"
        }
    }

    var systemImage: String {
        switch self {
        case .gitRepositories: "arrow.triangle.branch"
        case .noSync: "icloud.slash"
        case .nodeModules: "shippingbox.fill"
        case .xcodeDerivedData: "hammer.fill"
        case .buildArtifacts: "cube.box.fill"
        case .packageManagerCaches: "archivebox.fill"
        case .appCaches: "memorychip"
        case .logs: "doc.text.fill"
        case .ideMetadata: "chevron.left.forwardslash.chevron.right"
        }
    }

    var tintName: String {
        switch self {
        case .gitRepositories: "orange"
        case .noSync: "yellow"
        case .nodeModules: "green"
        case .xcodeDerivedData: "blue"
        case .buildArtifacts: "purple"
        case .packageManagerCaches: "teal"
        case .appCaches: "cyan"
        case .logs: "gray"
        case .ideMetadata: "indigo"
        }
    }

    var hint: String {
        switch self {
        case .gitRepositories: "Папки с .git — удаление затронет всю историю"
        case .noSync: "Папки и файлы с .nosync — локальные копии iCloud, не синхронизируются с облаком"
        case .nodeModules: "Зависимости npm/yarn/pnpm — можно восстановить через install"
        case .xcodeDerivedData: "Кэш сборок Xcode — безопасно очищать"
        case .buildArtifacts: "build, target, .next, __pycache__ и подобное"
        case .packageManagerCaches: "npm, yarn, pip, cargo, Homebrew и др."
        case .appCaches: "Кэши в ~/Library/Caches"
        case .logs: "Логи в ~/Library/Logs"
        case .ideMetadata: ".idea, .vscode, .gradle — настройки проектов"
        }
    }
}

struct CategorizedItem: Identifiable, Sendable, Hashable {
    let id: UUID
    let category: DiskCategory
    let node: DiskNode

    init(category: DiskCategory, node: DiskNode) {
        self.id = node.id
        self.category = category
        self.node = node
    }
}

struct CategoryIndex: Sendable {
    let itemsByCategory: [DiskCategory: [CategorizedItem]]
    let scannedAt: Date

    static let empty = CategoryIndex(itemsByCategory: [:], scannedAt: .now)

    var nonEmptyCategories: [DiskCategory] {
        DiskCategory.allCases.filter { totalSize(for: $0) > 0 }
    }

    func items(for category: DiskCategory) -> [CategorizedItem] {
        itemsByCategory[category] ?? []
    }

    func totalSize(for category: DiskCategory) -> Int64 {
        items(for: category).reduce(0) { $0 + $1.node.size }
    }

    func totalSize(for category: DiskCategory, trashedPaths: Set<String>) -> Int64 {
        items(for: category)
            .filter { !DiskNodeTrash.isTrashed($0.node, trashedPaths: trashedPaths) }
            .reduce(0) { $0 + $1.node.size }
    }

    func visibleItems(for category: DiskCategory, trashedPaths: Set<String>) -> [CategorizedItem] {
        items(for: category).filter { item in
            !DiskNodeTrash.isTrashed(item.node, trashedPaths: trashedPaths)
        }
    }

    func visibleCategories(trashedPaths: Set<String>) -> [DiskCategory] {
        DiskCategory.allCases.filter { totalSize(for: $0, trashedPaths: trashedPaths) > 0 }
    }

    var totalReclaimableSize: Int64 {
        nonEmptyCategories.reduce(0) { $0 + totalSize(for: $1) }
    }
}

enum BrowseMode: String, CaseIterable, Identifiable, Sendable {
    case tree
    case categories
    case aiAdvice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tree: "Дерево"
        case .categories: "Категории"
        case .aiAdvice: "ИИ"
        }
    }
}
