import Foundation
import GRDB

// MARK: - Search Past Conversations Tool

struct SearchConversationsTool: AITool {
    static let name = "search_past_conversations"
    static let description = "Search past conversation sessions by topic. Returns session titles, dates, and message counts. Use this when the user asks if you've discussed something before or wants to find a past conversation."
    static let inputSchema = ToolInputSchema(
        properties: [
            "query": ToolProperty(type: "string", description: "Search keyword to match against session titles and summaries"),
            "limit": ToolProperty(type: "integer", description: "Max results to return (default 5)")
        ],
        required: ["query"]
    )

    func execute(input: [String: JSONValue], db: DatabaseService) throws -> String {
        guard let query = input["query"]?.stringValue, !query.isEmpty else {
            throw ToolError.invalidInput("'query' parameter is required")
        }
        let limit = input["limit"]?.intValue ?? 5

        // Search sessions by title and summary
        let sessions = try db.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, title, summary, createdAt, lastMessageAt, messageCount
                FROM ai_sessions
                WHERE isArchived = 0 AND (title LIKE ? OR summary LIKE ?)
                ORDER BY lastMessageAt DESC
                LIMIT ?
                """, arguments: ["%\(query)%", "%\(query)%", limit])
        }

        if sessions.isEmpty {
            return try encodeToolResult([
                "sessions": .array([]),
                "message": .string("No past conversations found matching '\(query)'")
            ])
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        let items: [JSONValue] = sessions.map { row in
            let title: String = row["title"]
            let messageCount: Int = row["messageCount"]
            let lastMessageAt: Date = row["lastMessageAt"]
            let relativeDate = formatter.localizedString(for: lastMessageAt, relativeTo: Date())

            return .object([
                "title": .string(title),
                "message_count": .int(messageCount),
                "last_active": .string(relativeDate),
                "summary": .string((row["summary"] as? String) ?? "")
            ])
        }

        return try encodeToolResult([
            "sessions": .array(items),
            "count": .int(items.count)
        ])
    }
}
