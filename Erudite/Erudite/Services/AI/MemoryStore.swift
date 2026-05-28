import Foundation
import GRDB

// MARK: - AIObservation Model

struct AIObservation: Identifiable, Codable {
    let id: String
    let type: ObservationType
    let content: String
    let relatedWords: [String]?
    var confidence: Double
    let sourceSessionId: String?
    let createdAt: Date
    var lastConfirmedAt: Date
}

enum ObservationType: String, Codable, CaseIterable {
    case confusionPair = "confusion_pair"
    case weakness
    case strength
    case preference
    case insight
    case goal
}

// MARK: - Memory Store

/// Manages long-term memory (observations) and extraction orchestration.
final class MemoryStore {
    private let db: DatabaseService
    private let backgroundAI: BackgroundAI
    private var extractionWatermark: Int = 0

    init(db: DatabaseService, backgroundAI: BackgroundAI) {
        self.db = db
        self.backgroundAI = backgroundAI
    }

    // MARK: - AIObservations CRUD

    /// Save new observations (with deduplication)
    func saveAIObservations(_ observations: [AIObservation]) throws {
        guard !observations.isEmpty else { return }

        try db.dbQueue.write { db in
            for obs in observations {
                // Check for existing similar observation (same type + overlapping content)
                let existing = try Row.fetchOne(db, sql: """
                    SELECT id, confidence FROM ai_observations
                    WHERE type = ? AND content LIKE ?
                    LIMIT 1
                    """, arguments: [obs.type.rawValue, "%\(obs.content.prefix(30))%"])

                if let existing {
                    // Update existing: bump confidence and confirm time
                    let existingId: String = existing["id"]
                    let oldConf: Double = existing["confidence"]
                    let newConf = min(oldConf + 0.1, 1.0)
                    try db.execute(sql: """
                        UPDATE ai_observations SET confidence = ?, lastConfirmedAt = ? WHERE id = ?
                        """, arguments: [newConf, Date(), existingId])
                } else {
                    // Insert new
                    let relatedJson: String?
                    if let words = obs.relatedWords {
                        relatedJson = try? String(data: JSONEncoder().encode(words), encoding: .utf8)
                    } else {
                        relatedJson = nil
                    }

                    try db.execute(sql: """
                        INSERT INTO ai_observations (id, type, content, relatedWords, confidence, sourceSessionId, createdAt, lastConfirmedAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [
                            obs.id, obs.type.rawValue, obs.content, relatedJson,
                            obs.confidence, obs.sourceSessionId, obs.createdAt, obs.lastConfirmedAt
                        ])
                }
            }
        }
    }

    /// Fetch recent observations sorted by confidence + recency
    func fetchRecentAIObservations(limit: Int = 10) throws -> [AIObservation] {
        try db.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM ai_observations
                WHERE confidence > 0.3
                ORDER BY lastConfirmedAt DESC, confidence DESC
                LIMIT ?
                """, arguments: [limit])
            return rows.compactMap { Self.observationFromRow($0) }
        }
    }

    /// Search observations by keyword and optional type filter
    func searchAIObservations(query: String? = nil, type: String? = nil, limit: Int = 10) throws -> [AIObservation] {
        try db.dbQueue.read { db in
            var sql = "SELECT * FROM ai_observations WHERE confidence > 0.3"
            var args: [DatabaseValueConvertible] = []

            if let query, !query.isEmpty {
                sql += " AND content LIKE ?"
                args.append("%\(query)%")
            }
            if let type, !type.isEmpty {
                sql += " AND type = ?"
                args.append(type)
            }

            sql += " ORDER BY confidence DESC, lastConfirmedAt DESC LIMIT ?"
            args.append(limit)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.compactMap { Self.observationFromRow($0) }
        }
    }

    // MARK: - Extraction

    /// Check if extraction should be triggered
    func shouldExtract(messageCount: Int) -> Bool {
        let unextracted = messageCount - extractionWatermark
        return unextracted >= 5
    }

    /// Extract observations from recent messages and save them
    func extractAndSave(from messages: [ChatMessage], sessionId: String?) async throws {
        let messagesToExtract = Array(messages.dropFirst(extractionWatermark))
        guard !messagesToExtract.isEmpty else { return }

        let observations = try await backgroundAI.extractObservations(
            from: messagesToExtract,
            sessionId: sessionId
        )

        if !observations.isEmpty {
            try saveAIObservations(observations)
        }

        // Update watermark
        extractionWatermark = messages.count
    }

    /// Force extraction of all unprocessed messages (called on app background/close)
    func flushExtraction(from messages: [ChatMessage], sessionId: String?) async {
        guard messages.count > extractionWatermark else { return }
        try? await extractAndSave(from: messages, sessionId: sessionId)
    }

    /// Reset watermark (called when switching sessions)
    func resetWatermark() {
        extractionWatermark = 0
    }

    // MARK: - System Prompt Injection

    /// Build the memory section for the system prompt
    func buildMemorySection() throws -> String {
        let observations = try fetchRecentAIObservations(limit: 8)
        guard !observations.isEmpty else { return "" }

        var lines = ["## About This Learner (from memory)"]
        for obs in observations {
            lines.append("- [\(obs.type.rawValue)] \(obs.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func observationFromRow(_ row: Row) -> AIObservation? {
        guard let type = ObservationType(rawValue: row["type"] as String) else {
            return nil
        }

        var relatedWords: [String]?
        if let jsonStr = row["relatedWords"] as? String,
           let data = jsonStr.data(using: .utf8) {
            relatedWords = try? JSONDecoder().decode([String].self, from: data)
        }

        return AIObservation(
            id: row["id"],
            type: type,
            content: row["content"],
            relatedWords: relatedWords,
            confidence: row["confidence"],
            sourceSessionId: row["sourceSessionId"],
            createdAt: row["createdAt"],
            lastConfirmedAt: row["lastConfirmedAt"]
        )
    }
}
