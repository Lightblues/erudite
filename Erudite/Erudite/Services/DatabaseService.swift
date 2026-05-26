import Foundation
import GRDB

// MARK: - Database Service
// Wraps GRDB for all local persistence.

nonisolated(unsafe) final class DatabaseService: Sendable {
    let dbQueue: DatabaseQueue

    init() throws {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDirectory = appSupportURL.appendingPathComponent("Erudite", isDirectory: true)

        try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)

        let dbPath = dbDirectory.appendingPathComponent("erudite.db").path
        dbQueue = try DatabaseQueue(path: dbPath)
    }

    /// Initialize for testing with in-memory database
    init(inMemory: Bool) throws {
        dbQueue = try DatabaseQueue()
    }

    // MARK: - Schema

    func setupSchema() throws {
        try dbQueue.write { db in
            // Word table
            try db.create(table: "word", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("spelling", .text).notNull()
                t.column("phonetic", .text)
                t.column("sentiment", .text).notNull()
                t.column("frequency", .integer).notNull()
                t.column("data", .blob).notNull() // Full JSON-encoded Word
            }

            // Review card (FSRS state)
            try db.create(table: "reviewCard", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("wordId", .text).notNull()
                    .references("word", onDelete: .cascade)
                t.column("stability", .double).notNull().defaults(to: 0)
                t.column("difficulty", .double).notNull().defaults(to: 5.0)
                t.column("state", .integer).notNull().defaults(to: 0)
                t.column("dueDate", .datetime).notNull()
                t.column("reps", .integer).notNull().defaults(to: 0)
                t.column("lapses", .integer).notNull().defaults(to: 0)
                t.column("elapsedDays", .integer).notNull().defaults(to: 0)
                t.column("scheduledDays", .integer).notNull().defaults(to: 0)
                t.column("lastReview", .datetime)
            }

            // Review log
            try db.create(table: "reviewLog", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("cardId", .text).notNull()
                    .references("reviewCard", onDelete: .cascade)
                t.column("rating", .integer).notNull()
                t.column("state", .integer).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("elapsedDays", .integer).notNull()
                t.column("scheduledDays", .integer).notNull()
                t.column("reviewDuration", .double)
            }

            // Study session
            try db.create(table: "studySession", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("mode", .text).notNull()
                t.column("wordsStudied", .integer).notNull().defaults(to: 0)
                t.column("wordsNew", .integer).notNull().defaults(to: 0)
                t.column("wordsReviewed", .integer).notNull().defaults(to: 0)
                t.column("accuracy", .double)
                t.column("aiSummary", .text)
            }

            // Word lists
            try db.create(table: "wordList", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("isBuiltin", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }

            // Word list entries (many-to-many)
            try db.create(table: "wordListEntry", ifNotExists: true) { t in
                t.column("listId", .text).notNull()
                    .references("wordList", onDelete: .cascade)
                t.column("wordId", .text).notNull()
                    .references("word", onDelete: .cascade)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.primaryKey(["listId", "wordId"])
            }

            // AI content cache
            try db.create(table: "aiCache", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("wordId", .text).notNull()
                    .references("word", onDelete: .cascade)
                t.column("contentType", .text).notNull()
                t.column("content", .text).notNull()
                t.column("rating", .integer)
                t.column("createdAt", .datetime).notNull()
            }

            // Indexes
            try db.create(index: "idx_card_due", on: "reviewCard", columns: ["dueDate", "state"], ifNotExists: true)
            try db.create(index: "idx_card_word", on: "reviewCard", columns: ["wordId"], ifNotExists: true)
            try db.create(index: "idx_log_time", on: "reviewLog", columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_log_card", on: "reviewLog", columns: ["cardId"], ifNotExists: true)
            try db.create(index: "idx_ai_cache", on: "aiCache", columns: ["wordId", "contentType"], ifNotExists: true)
        }
    }

    // MARK: - Word Operations

    func insertWords(_ words: [Word]) throws {
        let encoder = JSONEncoder()
        try dbQueue.write { db in
            for word in words {
                let jsonData = try encoder.encode(word)
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO word (id, spelling, phonetic, sentiment, frequency, data)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        word.id,
                        word.spelling,
                        word.phonetic,
                        word.sentiment.rawValue,
                        word.frequency.rawValue,
                        jsonData
                    ]
                )
            }
        }
    }

    func fetchAllWords() throws -> [Word] {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT data FROM word ORDER BY frequency, spelling")
            return rows.compactMap { row in
                guard let data = row["data"] as? Data else { return nil }
                return try? decoder.decode(Word.self, from: data)
            }
        }
    }

    // MARK: - ReviewCard Operations

    func createCardsForNewWords(_ words: [Word]) throws {
        try dbQueue.write { db in
            for word in words {
                let existingCount = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM reviewCard WHERE wordId = ?",
                    arguments: [word.id]
                ) ?? 0

                if existingCount == 0 {
                    let card = ReviewCard(wordId: word.id)
                    try db.execute(
                        sql: """
                            INSERT INTO reviewCard (id, wordId, stability, difficulty, state, dueDate, reps, lapses, elapsedDays, scheduledDays, lastReview)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            card.id.uuidString,
                            card.wordId,
                            card.stability,
                            card.difficulty,
                            card.state.rawValue,
                            card.dueDate,
                            card.reps,
                            card.lapses,
                            card.elapsedDays,
                            card.scheduledDays,
                            card.lastReview
                        ]
                    )
                }
            }
        }
    }

    func fetchDueCards(now: Date = Date()) throws -> [ReviewCard] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM reviewCard WHERE state != 0 AND dueDate <= ? ORDER BY dueDate",
                arguments: [now]
            )
            return rows.map { rowToCard($0) }
        }
    }

    func fetchNewCards(limit: Int = 10) throws -> [ReviewCard] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM reviewCard WHERE state = 0 LIMIT ?",
                arguments: [limit]
            )
            return rows.map { rowToCard($0) }
        }
    }

    func updateCard(_ card: ReviewCard) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE reviewCard SET stability = ?, difficulty = ?, state = ?, dueDate = ?,
                    reps = ?, lapses = ?, elapsedDays = ?, scheduledDays = ?, lastReview = ?
                    WHERE id = ?
                    """,
                arguments: [
                    card.stability,
                    card.difficulty,
                    card.state.rawValue,
                    card.dueDate,
                    card.reps,
                    card.lapses,
                    card.elapsedDays,
                    card.scheduledDays,
                    card.lastReview,
                    card.id.uuidString
                ]
            )
        }
    }

    private func rowToCard(_ row: Row) -> ReviewCard {
        ReviewCard(
            id: UUID(uuidString: row["id"] as String) ?? UUID(),
            wordId: row["wordId"],
            stability: row["stability"],
            difficulty: row["difficulty"],
            elapsedDays: row["elapsedDays"],
            scheduledDays: row["scheduledDays"],
            reps: row["reps"],
            lapses: row["lapses"],
            state: CardState(rawValue: row["state"] as Int) ?? .new,
            dueDate: row["dueDate"],
            lastReview: row["lastReview"]
        )
    }
}
