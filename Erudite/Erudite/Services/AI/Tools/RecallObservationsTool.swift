import Foundation

// MARK: - Recall Observations Tool

struct RecallObservationsTool: AITool {
    static let name = "recall_observations"
    static let description = "Search your long-term memory about this learner. Returns past observations including confusion pairs, weaknesses, strengths, preferences, and goals. Use this when the user asks about past discussions or you need historical context."
    static let inputSchema = ToolInputSchema(
        properties: [
            "query": ToolProperty(type: "string", description: "Search keyword to filter observations (optional)"),
            "type": ToolProperty(type: "string", description: "Filter by observation type", enumValues: ["confusion_pair", "weakness", "strength", "preference", "insight", "goal"]),
            "limit": ToolProperty(type: "integer", description: "Max results to return (default 10)")
        ],
        required: nil
    )

    func execute(input: [String: JSONValue], db: DatabaseService) throws -> String {
        let query = input["query"]?.stringValue
        let type = input["type"]?.stringValue
        let limit = input["limit"]?.intValue ?? 10

        // Access MemoryStore via AppState
        guard let memoryStore = AppState.shared.memoryStore else {
            return try encodeToolResult(["observations": .array([]), "message": .string("Memory system not initialized")])
        }

        let observations = try memoryStore.searchAIObservations(query: query, type: type, limit: limit)

        if observations.isEmpty {
            return try encodeToolResult([
                "observations": .array([]),
                "message": .string("No observations found" + (query.map { " for '\($0)'" } ?? ""))
            ])
        }

        let items: [JSONValue] = observations.map { obs in
            JSONValue.object([
                "type": .string(obs.type.rawValue),
                "content": .string(obs.content),
                "confidence": .double(obs.confidence),
                "related_words": .array((obs.relatedWords ?? []).map { JSONValue.string($0) })
            ])
        }

        return try encodeToolResult([
            "observations": .array(items),
            "count": .int(items.count)
        ])
    }
}
