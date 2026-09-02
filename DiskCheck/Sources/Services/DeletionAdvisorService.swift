import Foundation

enum DeletionAdvisorService {
    static func detectBackend() async -> AIAdvisorBackend? {
        if AppleIntelligenceAdvisorBridge.isAvailable() {
            return .appleIntelligence
        }
        if let model = await OllamaAdvisorProvider.availableModel() {
            return .ollama(model: model)
        }
        return nil
    }

    static func suggest(
        root: DiskNode,
        categoryIndex: CategoryIndex,
        scope: AIAdviceScope = .overview,
        excludingPaths: Set<String> = [],
        backend: AIAdvisorBackend? = nil
    ) async -> AIDeletionAdvice {
        let summary: ScanTreeSummarizer.Summary
        switch scope {
        case .overview:
            summary = ScanTreeSummarizer.summarize(root: root, categoryIndex: categoryIndex)
        case .remainingFiles:
            summary = ScanTreeSummarizer.summarizeRemaining(
                root: root,
                excludingPaths: excludingPaths
            )
        }

        let allowedPaths = Set(summary.entries.map(\.path))
        let prompt = makePrompt(summary: summary, scope: scope)

        let resolvedBackend: AIAdvisorBackend?
        if let backend {
            resolvedBackend = backend
        } else {
            resolvedBackend = await detectBackend()
        }

        if let resolvedBackend {
            do {
                let raw: String
                switch resolvedBackend {
                case .appleIntelligence:
                    raw = try await AppleIntelligenceAdvisorBridge.suggest(prompt: prompt)
                case .ollama(let model):
                    raw = try await OllamaAdvisorProvider.suggest(prompt: prompt, model: model)
                case .rules:
                    raw = ""
                }

                let categories = DeletionAdviceParser.parse(
                    jsonText: raw,
                    root: root,
                    allowedPaths: allowedPaths
                )

                if !categories.isEmpty {
                    return AIDeletionAdvice(
                        providerName: resolvedBackend.displayName,
                        generatedAt: .now,
                        scope: scope,
                        categories: categories
                    )
                }
            } catch {
                // Fall through to rule-based suggestions for overview only.
            }
        }

        if scope == .overview {
            return RuleBasedAdvisorProvider.suggest(root: root, categoryIndex: categoryIndex)
        }

        return AIDeletionAdvice(
            providerName: resolvedBackend?.displayName ?? AIAdvisorBackend.rules.displayName,
            generatedAt: .now,
            scope: scope,
            categories: []
        )
    }

    private static func makePrompt(summary: ScanTreeSummarizer.Summary, scope: AIAdviceScope) -> String {
        let scopeInstructions: String
        switch scope {
        case .overview:
            scopeInstructions = """
            Проанализируй результаты сканирования диска и предложи категории для очистки.
            Фокус: крупнейшие папки, типовые кэши, артефакты сборки, логи.
            """
        case .remainingFiles:
            scopeInstructions = """
            Проанализируй дополнительные файлы и папки, которые не попали в основной обзор крупнейших объектов.
            Ищи: старые загрузки, забытые проекты, крупные медиафайлы, архивы, дубликаты, временные данные.
            """
        }

        return """
        \(scopeInstructions)

        Верни ТОЛЬКО JSON:
        {
          "categories": [
            {
              "title": "Название категории",
              "rationale": "Почему можно удалить",
              "safety": "safe|caution|dangerous",
              "paths": ["/полный/путь", "..."]
            }
          ]
        }

        Правила:
        - Используй только пути из списка кандидатов ниже
        - Не предлагай системные каталоги (/System, /Library без ~/Library)
        - Группируй логически
        - safety=safe для кэшей и логов, caution для IDE-метаданных и iCloud .nosync, dangerous для git и личных данных
        - Не более 8 категорий
        - В каждой категории не более 20 путей

        \(ScanTreeSummarizer.promptText(from: summary, scope: scope))
        """
    }
}
