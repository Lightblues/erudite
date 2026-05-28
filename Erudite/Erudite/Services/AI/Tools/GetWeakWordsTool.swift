import Foundation

// MARK: - Get Weak Words Tool

struct GetWeakWordsTool: AITool {
    static let name = "get_weak_words"
    static let description = "Returns the user's weakest words sorted by highest lapse count or lowest stability. Useful for identifying problem areas and words that need extra attention."
    static let inputSchema = ToolInputSchema(
        properties: [
            "limit": ToolProperty(type: "integer", description: "Number of words to return (default 10, max 20)"),
            "sort_by": ToolProperty(type: "string", description: "Sort criterion: 'lapses' (most forgotten) or 'stability' (most fragile)", enumValues: ["lapses", "stability"])
        ],
        required: nil
    )

    func execute(input: [String: JSONValue], db: DatabaseService) throws -> String {
        let limit = min(input["limit"]?.intValue ?? 10, 20)
        let sortBy = input["sort_by"]?.stringValue ?? "lapses"

        let weakCards = try db.fetchWeakCards(limit: limit, sortBy: sortBy, inBook: AppState.shared.activeBookId)

        if weakCards.isEmpty {
            return try encodeToolResult([
                "words": .array([]),
                "message": .string("No weak words found — the user hasn't studied enough yet or is doing great!")
            ])
        }

        let items: [JSONValue] = weakCards.map { (word, card) in
            .object([
                "word": .string(word.spelling),
                "lapses": .int(card.lapses),
                "stability_days": .double(card.stability),
                "difficulty": .double(card.difficulty),
                "state": .string(card.state.label)
            ])
        }

        let result: [String: JSONValue] = [
            "words": .array(items),
            "count": .int(items.count),
            "sort_by": .string(sortBy)
        ]

        return try encodeToolResult(result)
    }
}
