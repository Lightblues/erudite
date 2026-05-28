import Foundation
import GRDB

// MARK: - Search Past Conversations Tool

struct SearchConversationsTool: AITool {
    static let name = "search_past_conversations"
    static let description = "List or search past conversation sessions. When called without a query, returns all recent sessions. When called with a query, searches session titles and summaries. Use this when the user asks about past conversations or what you've discussed before."
    static let inputSchema = ToolInputSchema(
        properties: [
            "query": ToolProperty(type: "string", description: "Optional search keyword. Leave empty or omit to list all recent sessions."),
            "limit": ToolProperty(type: "integer", description: "Max results to return (default 10)")
        ],
        required: nil  // query is now optional
    )

    func execute(input: [String: JSONValue], db: DatabaseService) throws -> String {
        let query = input["query"]?.stringValue
        let limit = input["limit"]?.intValue ?? 10

        // Search or list sessions
        let sessions: [Row]
        if let query, !query.isEmpty {
            sessions = try db.dbQueue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, title, summary, createdAt, lastMessageAt, messageCount
                    FROM ai_sessions
                    WHERE isArchived = 0 AND (title LIKE ? OR summary LIKE ?)
                    ORDER BY lastMessageAt DESC
                    LIMIT ?
                    """, arguments: ["%\(query)%", "%\(query)%", limit])
            }
        } else {
            // No query — list all recent sessions
            sessions = try db.dbQueue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, title, summary, createdAt, lastMessageAt, messageCount
                    FROM ai_sessions
                    WHERE isArchived = 0
                    ORDER BY lastMessageAt DESC
                    LIMIT ?
                    """, arguments: [limit])
            }
        }

        if sessions.isEmpty {
            let msg = query.map { "No past conversations found matching '\($0)'" } ?? "No past conversations yet"
            return try encodeToolResult([
                "sessions": .array([]),
                "message": .string(msg)
            ])
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        let items: [JSONValue] = sessions.map { row in
            let title: String = row["title"]
            let messageCount: Int = row["messageCount"]
            let lastMessageAt: Date = row["lastMessageAt"]
            let relativeDate = formatter.localizedString(for: lastMessageAt, relativeTo: Date())

            return JSONValue.object([
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
