import Foundation

// MARK: - AI Provider Protocol

protocol AIProvider {
    /// Generate a text response from a prompt
    func generate(prompt: String, system: String?) async throws -> String

    /// Stream a text response (for longer outputs)
    func generateStream(prompt: String, system: String?) -> AsyncThrowingStream<String, Error>
}

// Default implementations
extension AIProvider {
    func generate(prompt: String) async throws -> String {
        try await generate(prompt: prompt, system: nil)
    }

    func generateStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        generateStream(prompt: prompt, system: nil)
    }
}
