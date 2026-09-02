import Foundation

enum RuleBasedAdvisorProvider {
    static func suggest(root: DiskNode, categoryIndex: CategoryIndex) -> AIDeletionAdvice {
        let categories: [AISuggestedCategory] = DiskCategory.allCases.compactMap { diskCategory in
            let items = categoryIndex.items(for: diskCategory).map { AISuggestedItem(node: $0.node) }
            guard !items.isEmpty else { return nil }

            return AISuggestedCategory(
                id: UUID(),
                title: diskCategory.title,
                rationale: diskCategory.hint,
                safety: safety(for: diskCategory),
                items: items
            )
        }

        return AIDeletionAdvice(
            providerName: AIAdvisorBackend.rules.displayName,
            generatedAt: .now,
            scope: .overview,
            categories: categories
        )
    }

    private static func safety(for category: DiskCategory) -> DeletionSafety {
        switch category {
        case .xcodeDerivedData, .nodeModules, .appCaches, .logs, .buildArtifacts, .packageManagerCaches:
            .safe
        case .ideMetadata:
            .caution
        case .noSync:
            .caution
        case .gitRepositories:
            .dangerous
        }
    }
}
