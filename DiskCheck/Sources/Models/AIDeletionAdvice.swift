import Foundation

enum DeletionSafety: String, Sendable, Codable {
    case safe
    case caution
    case dangerous

    var title: String {
        switch self {
        case .safe: "Безопасно"
        case .caution: "Осторожно"
        case .dangerous: "Рискованно"
        }
    }

    var systemImage: String {
        switch self {
        case .safe: "checkmark.shield"
        case .caution: "exclamationmark.triangle"
        case .dangerous: "xmark.octagon"
        }
    }
}

struct AISuggestedItem: Identifiable, Sendable, Hashable {
    let id: UUID
    let node: DiskNode

    init(node: DiskNode) {
        self.id = node.id
        self.node = node
    }
}

struct AISuggestedCategory: Identifiable, Sendable {
    let id: UUID
    let title: String
    let rationale: String
    let safety: DeletionSafety
    let items: [AISuggestedItem]

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.node.size }
    }
}

struct AIDeletionAdvice: Sendable {
    let providerName: String
    let generatedAt: Date
    let scope: AIAdviceScope
    let categories: [AISuggestedCategory]

    var totalReclaimableSize: Int64 {
        categories.reduce(0) { $0 + $1.totalSize }
    }
}

enum AIAdviceScope: Sendable {
    case overview
    case remainingFiles

    var sectionTitle: String {
        switch self {
        case .overview: "Основной обзор"
        case .remainingFiles: "Остальные файлы"
        }
    }
}

enum AIAdviceState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case unavailable(String)
    case failed(String)

    static func == (lhs: AIAdviceState, rhs: AIAdviceState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.ready, .ready):
            true
        case (.unavailable(let a), .unavailable(let b)), (.failed(let a), .failed(let b)):
            a == b
        default:
            false
        }
    }
}

enum AIAdvisorBackend: Sendable {
    case appleIntelligence
    case ollama(model: String)
    case rules

    var displayName: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .ollama(let model): "Ollama (\(model))"
        case .rules: "Встроенные правила"
        }
    }
}

struct AIAdviceResponseDTO: Decodable {
    struct Category: Decodable {
        let title: String
        let rationale: String
        let safety: String
        let paths: [String]
    }

    let categories: [Category]
}
