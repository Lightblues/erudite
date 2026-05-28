import Foundation

// MARK: - Get Word History Tool

struct GetWordHistoryTool: AITool {
    static let name = "get_word_history"
    static let description = "Returns the review history for a specific word, including times reviewed, lapse count, current FSRS stability and difficulty, last rating, and next due date."
    static let inputSchema = ToolInputSchema(
        properties: [
            "word": ToolProperty(type: "string", description: "The word spelling to look up (case-insensitive)")
        ],
        required: ["word"]
    )

    func execute(input: [String: JSONValue], db: DatabaseService) throws -> String {
        guard let wordSpelling = input["word"]?.stringValue else {
            throw ToolError.invalidInput("'word' parameter is required and must be a string")
        }

        // Look up the word
        guard let word = try db.fetchWord(bySpelling: wordSpelling) else {
            return try encodeToolResult([
                "error": .string("Word '\(wordSpelling)' not found in the database")
            ])
        }

        // Look up its review card
        guard let card = try db.fetchCardForWord(wordId: word.id) else {
            return try encodeToolResult([
                "word": .string(word.spelling),
                "status": .string("never_studied"),
                "message": .string("This word exists in the database but has not been studied yet")
            ])
        }

        // Get review logs for this card
        let logs = try db.fetchReviewLogsForCard(cardId: card.id)
        let lastRating = logs.first?.rating

        // Count ratings
        let againCount = logs.filter { $0.rating == .again }.count
        let hardCount = logs.filter { $0.rating == .hard }.count
        let goodCount = logs.filter { $0.rating == .good }.count
        let easyCount = logs.filter { $0.rating == .easy }.count

        let result: [String: JSONValue] = [
            "word": .string(word.spelling),
            "state": .string(card.state.label),
            "times_reviewed": .int(card.reps),
            "lapses": .int(card.lapses),
            "stability_days": .double(card.stability),
            "difficulty": .double(card.difficulty),
            "last_rating": .string(lastRating?.label ?? "none"),
            "next_due": .string(formatDate(card.dueDate)),
            "rating_breakdown": .object([
                "again": .int(againCount),
                "hard": .int(hardCount),
                "good": .int(goodCount),
                "easy": .int(easyCount)
            ])
        ]

        return try encodeToolResult(result)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
