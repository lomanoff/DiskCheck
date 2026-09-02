import Foundation

enum DeletionAdviceParser {
    static func parse(jsonText: String, root: DiskNode, allowedPaths: Set<String>) -> [AISuggestedCategory] {
        let payload = extractJSON(from: jsonText)
        guard let data = payload.data(using: .utf8),
              let dto = try? JSONDecoder().decode(AIAdviceResponseDTO.self, from: data)
        else { return [] }

        return dto.categories.compactMap { category in
            let items: [AISuggestedItem] = category.paths.compactMap { path in
                let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
                guard allowedPaths.contains(standardized) else { return nil }
                guard let node = ScanTreeSummarizer.findNode(path: standardized, in: root) else { return nil }
                return AISuggestedItem(node: node)
            }

            guard !items.isEmpty else { return nil }

            return AISuggestedCategory(
                id: UUID(),
                title: category.title.trimmingCharacters(in: .whitespacesAndNewlines),
                rationale: category.rationale.trimmingCharacters(in: .whitespacesAndNewlines),
                safety: DeletionSafety(rawValue: category.safety.lowercased()) ?? .caution,
                items: items.sorted { $0.node.size > $1.node.size }
            )
        }
    }

    static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }

        if let start = trimmed.range(of: "```json"),
           let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
            return String(trimmed[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }
}
