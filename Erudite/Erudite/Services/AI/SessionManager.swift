import Foundation
import GRDB

// MARK: - AI Session Model

struct AISession: Identifiable {
    let id: String
    var title: String
    var summary: String?
    let createdAt: Date
    var lastMessageAt: Date
    var messageCount: Int
    var isArchived: Bool

    init(
        id: String = UUID().uuidString,
        title: String = "New Conversation",
        summary: String? = nil,
        createdAt: Date = Date(),
        lastMessageAt: Date = Date(),
        messageCount: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
        self.isArchived = isArchived
    }
}

// MARK: - Session Manager

/// Manages AI chat session persistence: session CRUD, message load/save.
@Observable
final class SessionManager {
    private(set) var currentSession: AISession?
    private(set) var sessions: [AISession] = []

    private let db: DatabaseService

    init(db: DatabaseService) {
        self.db = db
    }

    // MARK: - Session Lifecycle

    /// Load the most recent session (or create one if none exists).
    /// Returns the messages for that session.
    func loadOrCreateLastSession() throws -> [ChatMessage] {
        // Fetch most recent non-archived session
        let session = try fetchLastSession()

        if let session {
            currentSession = session
            return try loadMessages(for: session.id)
        } else {
            // No sessions exist — create first one
            let newSession = try createSession()
            currentSession = newSession
            return []
        }
    }

    /// Create a new empty session and switch to it.
    func createNewSession() throws -> AISession {
        let session = try createSession()
        currentSession = session
        refreshSessionList()
        return session
    }

    /// Switch to an existing session, returning its messages.
    func switchToSession(id: String) throws -> [ChatMessage] {
        guard let session = sessions.first(where: { $0.id == id }) else {
            throw SessionError.notFound(id)
        }
        currentSession = session
        return try loadMessages(for: id)
    }

    /// Save a message to the current session.
    func saveMessage(_ message: ChatMessage) throws {
        guard let session = currentSession else { return }

        let encoder = JSONEncoder()
        let blocksJson: String?
        if let data = try? encoder.encode(message.blocks) {
            blocksJson = String(data: data, encoding: .utf8)
        } else {
            blocksJson = nil
        }

        try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO ai_messages (id, sessionId, role, content, blocksJson, isToolResult, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    message.id.uuidString,
                    session.id,
                    message.role.rawValue,
                    message.text,
                    blocksJson,
                    message.isToolResult,
                    message.timestamp
                ]
            )
        }

        // Session meta is updated separately via updateSessionMeta()
    }

    /// Update session title
    func updateTitle(_ title: String) {
        guard var session = currentSession else { return }
        session.title = title
        currentSession = session

        try? db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE ai_sessions SET title = ? WHERE id = ?",
                arguments: [title, session.id]
            )
        }
        refreshSessionList()
    }

    /// Delete a session and its messages
    func deleteSession(id: String) throws {
        try db.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM ai_sessions WHERE id = ?", arguments: [id])
        }
        sessions.removeAll { $0.id == id }
        if currentSession?.id == id {
            currentSession = nil
        }
    }

    /// Refresh the sessions list from DB
    func refreshSessionList() {
        sessions = (try? fetchAllSessions()) ?? []
    }

    // MARK: - Private Helpers

    private func createSession() throws -> AISession {
        let session = AISession()
        try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO ai_sessions (id, title, summary, createdAt, lastMessageAt, messageCount, isArchived)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    session.id,
                    session.title,
                    session.summary,
                    session.createdAt,
                    session.lastMessageAt,
                    session.messageCount,
                    session.isArchived
                ]
            )
        }
        return session
    }

    private func fetchLastSession() throws -> AISession? {
        try db.dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM ai_sessions WHERE isArchived = 0
                ORDER BY lastMessageAt DESC LIMIT 1
                """) else {
                return nil
            }
            return Self.sessionFromRow(row)
        }
    }

    private func fetchAllSessions() throws -> [AISession] {
        try db.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM ai_sessions WHERE isArchived = 0
                ORDER BY lastMessageAt DESC LIMIT 50
                """)
            return rows.map { Self.sessionFromRow($0) }
        }
    }

    private func loadMessages(for sessionId: String) throws -> [ChatMessage] {
        let decoder = JSONDecoder()
        return try db.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM ai_messages WHERE sessionId = ?
                ORDER BY createdAt ASC
                """, arguments: [sessionId])

            return rows.compactMap { row -> ChatMessage? in
                let role: MessageRole = row["role"] == "assistant" ? .assistant : .user
                let content: String = row["content"]
                let isToolResult: Bool = row["isToolResult"]
                let timestamp: Date = row["createdAt"]
                let idStr: String = row["id"]

                // Try to restore full content blocks
                var blocks: [ContentBlock] = [.text(content)]
                if let blocksJsonStr = row["blocksJson"] as? String,
                   let blocksData = blocksJsonStr.data(using: .utf8),
                   let decoded = try? decoder.decode([ContentBlock].self, from: blocksData) {
                    blocks = decoded
                }

                return ChatMessage(
                    id: UUID(uuidString: idStr) ?? UUID(),
                    role: role,
                    text: content,
                    blocks: blocks,
                    isToolResult: isToolResult,
                    timestamp: timestamp
                )
            }
        }
    }

    /// Update session metadata (public, called after saving messages)
    func updateSessionMeta() throws {
        guard var session = currentSession else { return }
        session.lastMessageAt = Date()
        currentSession = session

        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE ai_sessions SET lastMessageAt = ? WHERE id = ?",
                arguments: [Date(), session.id]
            )
        }
    }

    private static func sessionFromRow(_ row: Row) -> AISession {
        AISession(
            id: row["id"],
            title: row["title"],
            summary: row["summary"],
            createdAt: row["createdAt"],
            lastMessageAt: row["lastMessageAt"],
            messageCount: row["messageCount"],
            isArchived: row["isArchived"]
        )
    }
}

// MARK: - Errors

enum SessionError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "Session not found: \(id)"
        }
    }
}
