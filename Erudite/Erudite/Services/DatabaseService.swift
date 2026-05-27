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

            // Typing practice log
            try db.create(table: "typingLog", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("wordId", .text).notNull()
                    .references("word", onDelete: .cascade)
                t.column("bookId", .text)
                    .references("wordList", onDelete: .setNull)
                t.column("mistakes", .integer).notNull().defaults(to: 0)
                t.column("duration", .double)  // seconds to complete
                t.column("mode", .text).notNull().defaults(to: "typing")
                t.column("timestamp", .datetime).notNull()
            }
            try db.create(index: "idx_typing_word", on: "typingLog", columns: ["wordId"], ifNotExists: true)
            try db.create(index: "idx_typing_time", on: "typingLog", columns: ["timestamp"], ifNotExists: true)
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

    func fetchWords(inBook bookId: String) throws -> [Word] {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT w.data FROM word w
                JOIN wordListEntry wle ON wle.wordId = w.id
                WHERE wle.listId = ?
                ORDER BY wle.sortOrder
                """, arguments: [bookId])
            return rows.compactMap { row in
                guard let data = row["data"] as? Data else { return nil }
                return try? decoder.decode(Word.self, from: data)
            }
        }
    }

    func fetchWordsPage(inBook bookId: String, offset: Int, limit: Int) throws -> [Word] {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT w.data FROM word w
                JOIN wordListEntry wle ON wle.wordId = w.id
                WHERE wle.listId = ?
                ORDER BY wle.sortOrder
                LIMIT ? OFFSET ?
                """, arguments: [bookId, limit, offset])
            return rows.compactMap { row in
                guard let data = row["data"] as? Data else { return nil }
                return try? decoder.decode(Word.self, from: data)
            }
        }
    }

    func fetchWordCount(inBook bookId: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM wordListEntry WHERE listId = ?
                """, arguments: [bookId]) ?? 0
        }
    }

    func fetchWord(id: String) throws -> Word? {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT data FROM word WHERE id = ?", arguments: [id]) else {
                return nil
            }
            guard let data = row["data"] as? Data else { return nil }
            return try? decoder.decode(Word.self, from: data)
        }
    }

    func fetchWord(bySpelling spelling: String) throws -> Word? {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT data FROM word WHERE spelling = ? COLLATE NOCASE
                """, arguments: [spelling]) else {
                return nil
            }
            guard let data = row["data"] as? Data else { return nil }
            return try? decoder.decode(Word.self, from: data)
        }
    }

    /// Insert a single word (from API cache). Uses INSERT OR IGNORE to not overwrite existing enriched data.
    func insertCachedWord(_ word: Word) throws {
        let encoder = JSONEncoder()
        try dbQueue.write { db in
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

    /// Update (replace) a cached word with higher-quality data from a better source.
    func updateCachedWord(_ word: Word) throws {
        let encoder = JSONEncoder()
        try dbQueue.write { db in
            let jsonData = try encoder.encode(word)
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO word (id, spelling, phonetic, sentiment, frequency, data)
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

    func fetchWords(ids: [String]) throws -> [String: Word] {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = "SELECT id, data FROM word WHERE id IN (\(placeholders))"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(ids))
            var result: [String: Word] = [:]
            for row in rows {
                guard let data = row["data"] as? Data,
                      let word = try? decoder.decode(Word.self, from: data) else { continue }
                result[word.id] = word
            }
            return result
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

    func insertReviewLog(_ log: ReviewLog) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO reviewLog (cardId, rating, state, timestamp, elapsedDays, scheduledDays, reviewDuration)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    log.cardId.uuidString,
                    log.rating.rawValue,
                    log.state.rawValue,
                    log.timestamp,
                    log.elapsedDays,
                    log.scheduledDays,
                    log.reviewDuration
                ]
            )
        }
    }

    func fetchAllCards() throws -> [ReviewCard] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM reviewCard")
            return rows.map { self.rowToCard($0) }
        }
    }

    func fetchAllReviewLogs() throws -> [ReviewLog] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM reviewLog ORDER BY timestamp DESC")
            return rows.map { row in
                ReviewLog(
                    id: row["id"],
                    cardId: UUID(uuidString: row["cardId"] as String) ?? UUID(),
                    rating: Rating(rawValue: row["rating"] as Int) ?? .good,
                    state: CardState(rawValue: row["state"] as Int) ?? .new,
                    timestamp: row["timestamp"],
                    elapsedDays: row["elapsedDays"],
                    scheduledDays: row["scheduledDays"],
                    reviewDuration: row["reviewDuration"]
                )
            }
        }
    }

    func fetchReviewLogs(since date: Date) throws -> [ReviewLog] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM reviewLog WHERE timestamp >= ? ORDER BY timestamp DESC",
                arguments: [date]
            )
            return rows.map { row in
                ReviewLog(
                    id: row["id"],
                    cardId: UUID(uuidString: row["cardId"] as String) ?? UUID(),
                    rating: Rating(rawValue: row["rating"] as Int) ?? .good,
                    state: CardState(rawValue: row["state"] as Int) ?? .new,
                    timestamp: row["timestamp"],
                    elapsedDays: row["elapsedDays"],
                    scheduledDays: row["scheduledDays"],
                    reviewDuration: row["reviewDuration"]
                )
            }
        }
    }

    func fetchDueCount(now: Date = Date(), inBook bookId: String? = nil) throws -> Int {
        try dbQueue.read { db in
            if let bookId {
                return try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM reviewCard rc
                        JOIN wordListEntry wle ON wle.wordId = rc.wordId
                        WHERE wle.listId = ? AND rc.state != 0 AND rc.dueDate <= ?
                        """,
                    arguments: [bookId, now]
                ) ?? 0
            } else {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM reviewCard WHERE state != 0 AND dueDate <= ?",
                    arguments: [now]
                ) ?? 0
            }
        }
    }

    func fetchNewCount(inBook bookId: String? = nil) throws -> Int {
        try dbQueue.read { db in
            if let bookId {
                return try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM reviewCard rc
                        JOIN wordListEntry wle ON wle.wordId = rc.wordId
                        WHERE wle.listId = ? AND rc.state = 0
                        """,
                    arguments: [bookId]
                ) ?? 0
            } else {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewCard WHERE state = 0") ?? 0
            }
        }
    }

    func fetchLearnedCount(inBook bookId: String? = nil) throws -> Int {
        try dbQueue.read { db in
            if let bookId {
                return try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM reviewCard rc
                        JOIN wordListEntry wle ON wle.wordId = rc.wordId
                        WHERE wle.listId = ? AND rc.state != 0
                        """,
                    arguments: [bookId]
                ) ?? 0
            } else {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewCard WHERE state != 0") ?? 0
            }
        }
    }

    func fetchDueCards(now: Date = Date(), inBook bookId: String? = nil) throws -> [ReviewCard] {
        try dbQueue.read { db in
            let sql: String
            let args: StatementArguments
            if let bookId {
                sql = """
                    SELECT rc.* FROM reviewCard rc
                    JOIN wordListEntry wle ON wle.wordId = rc.wordId
                    WHERE wle.listId = ? AND rc.state != 0 AND rc.dueDate <= ?
                    ORDER BY rc.dueDate
                    """
                args = [bookId, now]
            } else {
                sql = "SELECT * FROM reviewCard WHERE state != 0 AND dueDate <= ? ORDER BY dueDate"
                args = [now]
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.map { self.rowToCard($0) }
        }
    }

    func fetchNewCards(limit: Int = 10, inBook bookId: String? = nil) throws -> [ReviewCard] {
        try dbQueue.read { db in
            let sql: String
            let args: StatementArguments
            if let bookId {
                sql = """
                    SELECT rc.* FROM reviewCard rc
                    JOIN wordListEntry wle ON wle.wordId = rc.wordId
                    WHERE wle.listId = ? AND rc.state = 0
                    ORDER BY wle.sortOrder
                    LIMIT ?
                    """
                args = [bookId, limit]
            } else {
                sql = "SELECT * FROM reviewCard WHERE state = 0 LIMIT ?"
                args = [limit]
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.map { self.rowToCard($0) }
        }
    }

    // MARK: - WordBook Operations

    func insertWordBook(_ book: WordBook) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO wordList (id, name, description, isBuiltin, createdAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [book.id, book.name, book.description, book.isBuiltin, book.createdAt]
            )
        }
    }

    func fetchWordBooks() throws -> [WordBook] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT wl.*, COUNT(wle.wordId) as wordCount
                FROM wordList wl
                LEFT JOIN wordListEntry wle ON wle.listId = wl.id
                GROUP BY wl.id
                ORDER BY wl.name
                """)
            return rows.map { row in
                WordBook(
                    id: row["id"],
                    name: row["name"],
                    description: row["description"],
                    wordCount: row["wordCount"],
                    isBuiltin: row["isBuiltin"]
                )
            }
        }
    }

    func insertWordBookEntries(bookId: String, wordIds: [String]) throws {
        try dbQueue.write { db in
            for (index, wordId) in wordIds.enumerated() {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO wordListEntry (listId, wordId, sortOrder) VALUES (?, ?, ?)",
                    arguments: [bookId, wordId, index]
                )
            }
        }
    }

    // MARK: - Typing Log

    func insertTypingLog(wordId: String, bookId: String?, mistakes: Int, duration: TimeInterval?, mode: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO typingLog (wordId, bookId, mistakes, duration, mode, timestamp)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [wordId, bookId, mistakes, duration, mode, Date()]
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
