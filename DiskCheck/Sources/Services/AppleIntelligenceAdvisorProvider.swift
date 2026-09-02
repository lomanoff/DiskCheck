import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
enum AppleIntelligenceAdvisorProvider {
    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            true
        default:
            false
        }
    }

    static func suggest(prompt: String) async throws -> String {
        let instructions = """
        Ты помощник по очистке диска macOS. Отвечай только валидным JSON без markdown.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif

enum AppleIntelligenceAdvisorBridge {
    static func isAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AppleIntelligenceAdvisorProvider.isAvailable
        }
        #endif
        return false
    }

    static func suggest(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await AppleIntelligenceAdvisorProvider.suggest(prompt: prompt)
        }
        #endif
        throw AppleIntelligenceError.unavailable
    }

    enum AppleIntelligenceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Apple Intelligence недоступна на этом Mac"
        }
    }
}
