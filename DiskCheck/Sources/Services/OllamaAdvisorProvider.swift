import Foundation

enum OllamaAdvisorProvider {
    private static let baseURL = URL(string: "http://127.0.0.1:11434")!
    private static let preferredModels = [
        "llama3.2",
        "llama3.1",
        "mistral",
        "qwen2.5",
        "gemma2",
    ]

    static func availableModel() async -> String? {
        guard let url = URL(string: "/api/tags", relativeTo: baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return nil }

        let names = models.compactMap { $0["name"] as? String }
        for preferred in preferredModels {
            if let match = names.first(where: { $0.hasPrefix(preferred) }) {
                return match
            }
        }
        return names.first
    }

    static func suggest(prompt: String, model: String) async throws -> String {
        guard let url = URL(string: "/api/generate", relativeTo: baseURL) else {
            throw AdvisorError.invalidEndpoint
        }

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": "json",
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AdvisorError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String
        else {
            throw AdvisorError.invalidResponse
        }

        return text
    }

    enum AdvisorError: LocalizedError {
        case invalidEndpoint
        case requestFailed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: "Некорректный адрес Ollama"
            case .requestFailed: "Ollama не ответила"
            case .invalidResponse: "Не удалось разобрать ответ Ollama"
            }
        }
    }
}
