import Foundation

// MARK: - Claude Provider (Stub)
// Will implement actual Anthropic API calls in a future issue.

final class ClaudeProvider: AIProvider {
    private let apiKey: String
    private let model: String

    init(apiKey: String = "", model: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.model = model
    }

    func generate(prompt: String, system: String?) async throws -> String {
        // Stub: return a placeholder response
        return "[AI response placeholder — Claude API not yet connected]"
    }

    func generateStream(prompt: String, system: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("[AI streaming placeholder]")
            continuation.finish()
        }
    }
}
