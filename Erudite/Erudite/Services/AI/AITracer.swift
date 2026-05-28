import Foundation
import GRDB

// MARK: - AI Trace

/// Records every AI API call for debugging and cost analysis.
/// Stored in SQLite for querying and export.
struct AITrace: Identifiable {
    let id: String
    let timestamp: Date
    let model: String
    let purpose: String          // "chat", "extraction", "title", "tip"
    let inputTokens: Int
    let outputTokens: Int
    let cacheHit: Bool
    let latencyMs: Int
    let toolCalls: [String]      // tool names called in this request
    let error: String?
    let sessionId: String?
}

// MARK: - AI Tracer

/// Records and queries AI API call traces.
final class AITracer {
    static let shared = AITracer()

    private var db: DatabaseService?

    private init() {}

    /// Set database reference (called during app init)
    func configure(db: DatabaseService) {
        self.db = db
    }

    /// Record a completed API call
    func record(
        model: String,
        purpose: String,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheHit: Bool = false,
        latencyMs: Int = 0,
        toolCalls: [String] = [],
        error: String? = nil,
        sessionId: String? = nil
    ) {
        guard let db else { return }

        let trace = AITrace(
            id: UUID().uuidString,
            timestamp: Date(),
            model: model,
            purpose: purpose,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheHit: cacheHit,
            latencyMs: latencyMs,
            toolCalls: toolCalls,
            error: error,
            sessionId: sessionId
        )

        do {
            let toolsJson = (try? JSONEncoder().encode(toolCalls))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            try db.dbQueue.write { dbConn in
                try dbConn.execute(sql: """
                    INSERT INTO ai_traces (id, timestamp, model, purpose, inputTokens, outputTokens, cacheHit, latencyMs, toolCalls, error, sessionId)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        trace.id, trace.timestamp, trace.model, trace.purpose,
                        trace.inputTokens, trace.outputTokens, trace.cacheHit ? 1 : 0,
                        trace.latencyMs, toolsJson, trace.error, trace.sessionId
                    ])
            }
        } catch {
            Log.ai.error("Failed to record trace", error: error)
        }
    }

    /// Fetch recent traces (for debug panel)
    func fetchRecent(limit: Int = 50) -> [AITrace] {
        guard let db else { return [] }
        do {
            return try db.dbQueue.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT * FROM ai_traces ORDER BY timestamp DESC LIMIT ?
                    """, arguments: [limit])
                return rows.compactMap { Self.traceFromRow($0) }
            }
        } catch {
            return []
        }
    }

    /// Total cost stats for today
    func todayStats() -> (calls: Int, inputTokens: Int, outputTokens: Int, cacheHits: Int) {
        guard let db else { return (0, 0, 0, 0) }
        let today = Calendar.current.startOfDay(for: Date())
        do {
            return try db.dbQueue.read { dbConn in
                guard let row = try Row.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) as calls,
                           COALESCE(SUM(inputTokens), 0) as input,
                           COALESCE(SUM(outputTokens), 0) as output,
                           COALESCE(SUM(cacheHit), 0) as hits
                    FROM ai_traces WHERE timestamp >= ?
                    """, arguments: [today]) else {
                    return (0, 0, 0, 0)
                }
                return (row["calls"], row["input"], row["output"], row["hits"])
            }
        } catch {
            return (0, 0, 0, 0)
        }
    }

    private static func traceFromRow(_ row: Row) -> AITrace? {
        let toolsJson: String = row["toolCalls"] ?? "[]"
        let tools = (try? JSONDecoder().decode([String].self, from: toolsJson.data(using: .utf8) ?? Data())) ?? []

        return AITrace(
            id: row["id"],
            timestamp: row["timestamp"],
            model: row["model"],
            purpose: row["purpose"],
            inputTokens: row["inputTokens"],
            outputTokens: row["outputTokens"],
            cacheHit: (row["cacheHit"] as Int) != 0,
            latencyMs: row["latencyMs"],
            toolCalls: tools,
            error: row["error"],
            sessionId: row["sessionId"]
        )
    }
}
