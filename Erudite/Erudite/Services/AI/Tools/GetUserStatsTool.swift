import Foundation

// MARK: - Get User Stats Tool

struct GetUserStatsTool: AITool {
    static let name = "get_user_stats"
    static let description = "Returns the user's overall learning statistics including total words in active book, words due today, words learned (no longer new), average accuracy from recent reviews, and current study streak."
    static let inputSchema = ToolInputSchema()

    func execute(input: [String: JSONValue], db: DatabaseService) throws -> String {
        let bookId = AppState.shared.activeBookId

        let dueCount = try db.fetchDueCount(inBook: bookId)
        let newCount = try db.fetchNewCount(inBook: bookId)
        let learnedCount = try db.fetchLearnedCount(inBook: bookId)
        let accuracy = try db.fetchRecentAccuracy()
        let streak = try db.fetchStudyStreak()
        let bookName = AppState.shared.activeBook?.name ?? "All books"

        let result: [String: JSONValue] = [
            "active_book": .string(bookName),
            "total_learned": .int(learnedCount),
            "due_today": .int(dueCount),
            "new_remaining": .int(newCount),
            "recent_accuracy": .double(accuracy),
            "streak_days": .int(streak)
        ]

        return try encodeToolResult(result)
    }
}
