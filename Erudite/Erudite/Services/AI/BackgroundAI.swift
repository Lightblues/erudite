import Foundation

// MARK: - Background AI

/// Handles background AI tasks using the fast model (non-user-facing).
/// Used for: observation extraction, session title generation, etc.
final class BackgroundAI {
    private let client: AnthropicClient

    init(client: AnthropicClient) {
        self.client = client
    }

    // MARK: - Generic Generation

    /// Generate a response using the fast model. Collects the full streaming response.
    func generate(prompt: String, system: String? = nil) async throws -> String {
        let systemBlocks = system.map { [AnthropicRequest.SystemBlock(text: $0)] }

        let request = AnthropicRequest(
            model: AppConfig.shared.resolvedFastModel,
            max_tokens: 1024,
            system: systemBlocks,
            messages: [APIMessage(role: .user, content: [.text(prompt)])],
            tools: nil,
            stream: true  // Use streaming (some proxies only support it)
        )

        let stream = try await client.stream(
            request: request,
            apiKey: AppConfig.shared.aiApiKey,
            baseURL: AppConfig.shared.resolvedAIBaseURL
        )

        // Collect full response from stream
        var text = ""
        for try await event in stream {
            if case .contentBlockDelta(_, let delta) = event {
                if case .textDelta(let chunk) = delta {
                    text += chunk
                }
            }
        }
        return text
    }

    // MARK: - Observation Extraction

    /// Extract observations from recent messages.
    func extractObservations(from messages: [ChatMessage], sessionId: String?) async throws -> [AIObservation] {
        // Only include user-visible messages (no tool results)
        let visibleMessages = messages.filter { !$0.isToolResult }
        guard visibleMessages.count >= 2 else { return [] }

        // Format messages for the prompt
        let formatted = visibleMessages.suffix(10).map { msg in
            let prefix = msg.role == .user ? "User" : "AI"
            return "\(prefix): \(msg.text)"
        }.joined(separator: "\n")

        let prompt = """
        From this tutoring conversation, extract observations about the learner worth remembering for future sessions.

        Categories: confusion_pair, weakness, strength, preference, insight, goal
        Rules:
        - Only extract HIGH confidence observations
        - Be specific (include word names, root families, etc.)
        - Max 3 per extraction (quality over quantity)
        - Return [] if nothing notable
        - Output ONLY the JSON array, no other text

        Conversation:
        \(formatted)

        Return JSON array: [{"type": "...", "content": "...", "related_words": [...], "confidence": 0.0-1.0}]
        """

        let response = try await generate(prompt: prompt)

        // Parse JSON response
        return parseObservations(from: response, sessionId: sessionId)
    }

    // MARK: - Title Generation

    /// Generate a short title for a session based on its first messages.
    func generateTitle(from messages: [ChatMessage]) async throws -> String {
        let visibleMessages = messages.filter { !$0.isToolResult }
        guard !visibleMessages.isEmpty else { return "New Conversation" }

        let formatted = visibleMessages.prefix(4).map { msg in
            let prefix = msg.role == .user ? "User" : "AI"
            return "\(prefix): \(msg.text.prefix(200))"
        }.joined(separator: "\n")

        let prompt = """
        Generate a short title (3-6 words, Chinese preferred) for this conversation.
        Output ONLY the title, nothing else.

        Conversation:
        \(formatted)
        """

        let title = try await generate(prompt: prompt)
        // Clean up: remove quotes, trim, limit length
        let cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .prefix(50)
        return cleaned.isEmpty ? "New Conversation" : String(cleaned)
    }

    // MARK: - Helpers

    private func parseObservations(from response: String, sessionId: String?) -> [AIObservation] {
        // Try to extract JSON array from the response
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON array in response (might have surrounding text)
        guard let startIdx = trimmed.firstIndex(of: "["),
              let endIdx = trimmed.lastIndex(of: "]") else {
            return []
        }

        let jsonStr = String(trimmed[startIdx...endIdx])
        guard let data = jsonStr.data(using: .utf8) else { return [] }

        struct RawObs: Decodable {
            let type: String
            let content: String
            let related_words: [String]?
            let confidence: Double?
        }

        guard let rawList = try? JSONDecoder().decode([RawObs].self, from: data) else {
            return []
        }

        let now = Date()
        return rawList.compactMap { raw in
            guard let obsType = ObservationType(rawValue: raw.type) else { return nil }
            return AIObservation(
                id: UUID().uuidString,
                type: obsType,
                content: raw.content,
                relatedWords: raw.related_words,
                confidence: raw.confidence ?? 0.8,
                sourceSessionId: sessionId,
                createdAt: now,
                lastConfirmedAt: now
            )
        }
    }
}
