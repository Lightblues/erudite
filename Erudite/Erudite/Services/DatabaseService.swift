import Foundation
import GRDB

// MARK: - Database Service
// Wraps GRDB for all local persistence.

nonisolated final class DatabaseService: Sendable {
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
            // Library does ORDER BY w.spelling COLLATE NOCASE on every page —
            // give it a covering index so we don't full-scan + sort 13K rows.
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_word_spelling ON word (spelling COLLATE NOCASE)")
            // Book-order browsing relies on (listId, sortOrder); the existing
            // PRIMARY KEY on (listId, wordId) doesn't help. Add it so paging
            // through a Book in sortOrder is index-driven.
            try db.create(index: "idx_wle_list_order", on: "wordListEntry", columns: ["listId", "sortOrder"], ifNotExists: true)

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

            // AI Chat Sessions
            try db.create(table: "ai_sessions", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull().defaults(to: "New Conversation")
                t.column("summary", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastMessageAt", .datetime).notNull()
                t.column("messageCount", .integer).notNull().defaults(to: 0)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
            }

            // AI Chat Messages
            try db.create(table: "ai_messages", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("sessionId", .text).notNull()
                    .references("ai_sessions", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("blocksJson", .text)
                t.column("isToolResult", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_ai_msg_session", on: "ai_messages", columns: ["sessionId", "createdAt"], ifNotExists: true)

            // AI Observations (long-term memory)
            try db.create(table: "ai_observations", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("content", .text).notNull()
                t.column("relatedWords", .text)
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("sourceSessionId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastConfirmedAt", .datetime).notNull()
            }
            try db.create(index: "idx_ai_obs_type", on: "ai_observations", columns: ["type"], ifNotExists: true)
            try db.create(index: "idx_ai_obs_confidence", on: "ai_observations", columns: ["confidence"], ifNotExists: true)

            // AI API call traces (for debugging and cost analysis)
            try db.create(table: "ai_traces", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("timestamp", .datetime).notNull()
                t.column("model", .text).notNull()
                t.column("purpose", .text).notNull()
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("cacheHit", .boolean).notNull().defaults(to: false)
                t.column("latencyMs", .integer).notNull().defaults(to: 0)
                t.column("toolCalls", .text)
                t.column("error", .text)
                t.column("sessionId", .text)
            }
            try db.create(index: "idx_ai_traces_time", on: "ai_traces", columns: ["timestamp"], ifNotExists: true)

            // User-generated content (mnemonics, notes, ...).
            // Single table keyed by `type` so we can add new content categories
            // without schema migration. `content` is plain text; we don't try
            // to be clever about formats.
            try db.create(table: "user_content", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("wordId", .text).notNull()
                    .references("word", onDelete: .cascade)
                t.column("type", .text).notNull()       // "mnemonic" | "note" | future
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_user_content_word", on: "user_content", columns: ["wordId", "type"], ifNotExists: true)

            // Generic key/value metadata.
            // Used for tracking the bundled data version (so we can upgrade
            // pre-existing words when words.json ships a newer enrichment).
            // Other future uses: schema migration markers, last-seen-changelog,
            // feature flags. Stays small (< 100 rows) so no need for indexes.
            try db.create(table: "meta", ifNotExists: true) { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
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

    /// Bulk-upgrade word.data for words already in the DB.
    ///
    /// Used by WordLoader when the bundled words.json version moves forward
    /// (e.g. v1.0 → v3.0 ai-enriched). For each input word:
    /// - if it exists: UPDATE the row (preserving foreign key relationships)
    /// - if it's new: INSERT a fresh row + create a ReviewCard for it
    ///
    /// CRITICAL: We must NOT use `INSERT OR REPLACE` here. SQLite implements
    /// REPLACE as DELETE-then-INSERT when there's a primary-key conflict, and
    /// reviewCard.wordId has `ON DELETE CASCADE` — so a naive REPLACE would
    /// wipe out the user's entire FSRS progress. UPDATE on the same primary
    /// key avoids triggering the DELETE and keeps reviewCard / reviewLog /
    /// user_content untouched.
    ///
    /// Returns (`existingUpdated`, `newInserted`) so the caller can log a
    /// useful summary.
    func upsertWordData(_ words: [Word]) throws -> (existingUpdated: Int, newInserted: Int) {
        let encoder = JSONEncoder()
        var updated = 0
        var inserted = 0
        try dbQueue.write { db in
            // Pull existing IDs once so we can pick UPDATE vs INSERT per row.
            let existingIds = Set(try String.fetchAll(db, sql: "SELECT id FROM word"))
            for word in words {
                let jsonData = try encoder.encode(word)
                if existingIds.contains(word.id) {
                    try db.execute(
                        sql: """
                            UPDATE word
                            SET spelling = ?, phonetic = ?, sentiment = ?, frequency = ?, data = ?
                            WHERE id = ?
                            """,
                        arguments: [
                            word.spelling,
                            word.phonetic,
                            word.sentiment.rawValue,
                            word.frequency.rawValue,
                            jsonData,
                            word.id
                        ]
                    )
                    updated += 1
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO word (id, spelling, phonetic, sentiment, frequency, data)
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
                    inserted += 1
                }
            }
        }
        return (updated, inserted)
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

    // MARK: - WordSummary (lightweight projection for list views)
    //
    // Query strategy: project only the fields list rows need (id, spelling,
    // phonetic, freq, first def, pos, hasMnemonic, cardState). All filters
    // (book/tier/state/search) and sorts run in SQL — never load + filter in
    // Swift over 13K Word JSON blobs.
    //
    // Search uses LIKE on spelling + first Chinese definition (case-insensitive).
    // Card state comes from a LEFT JOIN on reviewCard (NULL = no card row, treat as new).
    // Mnemonic detection uses json_array_length on the bundled mnemonics field;
    // user-added mnemonics (future user_content table) will need an OR clause here.

    func fetchWordSummaries(
        book: String? = nil,
        state: WordStateFilter = .all,
        search: String? = nil,
        sort: WordSort = .bookOrder,
        limit: Int = 200,
        offset: Int = 0
    ) throws -> [WordSummary] {
        try dbQueue.read { db in
            let (sql, args) = Self.buildSummaryQuery(
                book: book, state: state, search: search,
                sort: sort, limit: limit, offset: offset, countOnly: false
            )
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.map(Self.rowToSummary)
        }
    }

    func fetchWordSummaryCount(
        book: String? = nil,
        state: WordStateFilter = .all,
        search: String? = nil
    ) throws -> Int {
        try dbQueue.read { db in
            let (sql, args) = Self.buildSummaryQuery(
                book: book, state: state, search: search,
                sort: .alphabetical, limit: 0, offset: 0, countOnly: true
            )
            return try Int.fetchOne(db, sql: sql, arguments: args) ?? 0
        }
    }

    /// Total word count in the bundled DB (book == nil → all words).
    func fetchTotalWordCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM word") ?? 0
        }
    }

    private static func buildSummaryQuery(
        book: String?,
        state: WordStateFilter,
        search: String?,
        sort: WordSort,
        limit: Int,
        offset: Int,
        countOnly: Bool
    ) -> (String, StatementArguments) {
        var args: [DatabaseValueConvertible] = []
        var clauses: [String] = []

        // bookOrder needs wle.sortOrder. Always INNER JOIN wordListEntry when a
        // book is set so we can ORDER BY it; without a book selected, bookOrder
        // silently falls back to alphabetical (no wle column to sort on).
        let select: String
        if countOnly {
            select = "SELECT COUNT(*)"
        } else {
            // json_extract works on the BLOB column because GRDB stores UTF-8 JSON
            // bytes; SQLite's JSON1 parser accepts the byte sequence directly.
            select = """
                SELECT
                  w.id AS id,
                  w.spelling AS spelling,
                  w.phonetic AS phonetic,
                  w.frequency AS frequency,
                  json_extract(w.data, '$.definitions[0].chinese') AS firstDefZh,
                  json_extract(w.data, '$.definitions[0].partOfSpeech') AS posLabel,
                  CASE
                    WHEN json_extract(w.data, '$.mnemonics') IS NOT NULL
                      AND json_array_length(json_extract(w.data, '$.mnemonics')) > 0
                    THEN 1 ELSE 0
                  END AS hasMnemonic,
                  rc.state AS cardState
                """
        }

        var from = "FROM word w LEFT JOIN reviewCard rc ON rc.wordId = w.id"
        if let book {
            from += " INNER JOIN wordListEntry wle ON wle.wordId = w.id AND wle.listId = ?"
            args.append(book)
        }

        switch state {
        case .all:
            break
        case .new:
            // No card row OR card.state == 0 (new)
            clauses.append("(rc.state IS NULL OR rc.state = 0)")
        case .learning:
            clauses.append("rc.state IN (1, 3)")
        case .review:
            clauses.append("rc.state = 2")
        case .mature:
            // Review state with stability over 21 days — rough "mature" bucket
            clauses.append("rc.state = 2 AND rc.stability >= 21")
        }

        if let search, !search.isEmpty {
            let pattern = "%\(search)%"
            clauses.append("""
                (w.spelling LIKE ? OR json_extract(w.data, '$.definitions[0].chinese') LIKE ?)
                """)
            args.append(pattern)
            args.append(pattern)
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")

        let orderBy: String
        if countOnly {
            orderBy = ""
        } else {
            switch sort {
            case .bookOrder:
                if book != nil {
                    orderBy = "ORDER BY wle.sortOrder, w.spelling COLLATE NOCASE"
                } else {
                    // No book picked → "Book Order" is meaningless; fall back to A→Z.
                    orderBy = "ORDER BY w.spelling COLLATE NOCASE"
                }
            case .alphabetical:
                orderBy = "ORDER BY w.spelling COLLATE NOCASE"
            case .dueDate:
                // NULL dueDate (new cards / no card) sorts last; among non-null, soonest first
                orderBy = "ORDER BY (rc.dueDate IS NULL), rc.dueDate ASC, w.spelling COLLATE NOCASE"
            case .lapses:
                orderBy = "ORDER BY (rc.lapses IS NULL), rc.lapses DESC, w.spelling COLLATE NOCASE"
            }
        }

        let limitClause: String
        if countOnly {
            limitClause = ""
        } else {
            limitClause = "LIMIT ? OFFSET ?"
            args.append(limit)
            args.append(offset)
        }

        let sql = [select, from, whereClause, orderBy, limitClause]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return (sql, StatementArguments(args))
    }

    // MARK: - WordSummary convenience queries (Today / Plan)

    /// Words that are due for review now, projected as summaries (sorted by dueDate).
    /// Used by Today preview and Plan due-backlog. Excludes new cards.
    func fetchDueSummaries(now: Date = Date(), inBook bookId: String? = nil, limit: Int = 50) throws -> [WordSummary] {
        try dbQueue.read { db in
            var args: [DatabaseValueConvertible] = []
            var from = "FROM word w INNER JOIN reviewCard rc ON rc.wordId = w.id"
            if let bookId {
                from += " INNER JOIN wordListEntry wle ON wle.wordId = w.id AND wle.listId = ?"
                args.append(bookId)
            }
            let sql = """
                SELECT
                  w.id AS id,
                  w.spelling AS spelling,
                  w.phonetic AS phonetic,
                  w.frequency AS frequency,
                  json_extract(w.data, '$.definitions[0].chinese') AS firstDefZh,
                  json_extract(w.data, '$.definitions[0].partOfSpeech') AS posLabel,
                  CASE
                    WHEN json_extract(w.data, '$.mnemonics') IS NOT NULL
                      AND json_array_length(json_extract(w.data, '$.mnemonics')) > 0
                    THEN 1 ELSE 0
                  END AS hasMnemonic,
                  rc.state AS cardState,
                  rc.dueDate AS dueDate
                \(from)
                WHERE rc.state != 0 AND rc.dueDate <= ?
                ORDER BY rc.dueDate ASC
                LIMIT ?
                """
            args.append(now)
            args.append(limit)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map(Self.rowToSummary)
        }
    }

    /// New cards (state = 0), in book sortOrder if a book is given.
    /// Used by Today preview and Plan new-words queue.
    func fetchNewWordSummaries(inBook bookId: String? = nil, limit: Int = 50) throws -> [WordSummary] {
        try dbQueue.read { db in
            var args: [DatabaseValueConvertible] = []
            let from: String
            let order: String
            if let bookId {
                from = """
                    FROM word w
                    INNER JOIN reviewCard rc ON rc.wordId = w.id
                    INNER JOIN wordListEntry wle ON wle.wordId = w.id AND wle.listId = ?
                    """
                args.append(bookId)
                order = "ORDER BY wle.sortOrder ASC"
            } else {
                from = "FROM word w INNER JOIN reviewCard rc ON rc.wordId = w.id"
                order = "ORDER BY w.frequency, w.spelling COLLATE NOCASE"
            }
            let sql = """
                SELECT
                  w.id AS id,
                  w.spelling AS spelling,
                  w.phonetic AS phonetic,
                  w.frequency AS frequency,
                  json_extract(w.data, '$.definitions[0].chinese') AS firstDefZh,
                  json_extract(w.data, '$.definitions[0].partOfSpeech') AS posLabel,
                  CASE
                    WHEN json_extract(w.data, '$.mnemonics') IS NOT NULL
                      AND json_array_length(json_extract(w.data, '$.mnemonics')) > 0
                    THEN 1 ELSE 0
                  END AS hasMnemonic,
                  rc.state AS cardState
                \(from)
                WHERE rc.state = 0
                \(order)
                LIMIT ?
                """
            args.append(limit)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map(Self.rowToSummary)
        }
    }

    /// Count of due cards grouped by day (next N days), for the Plan workload chart.
    /// Returns one entry per day in the range with explicit zeros (calendar gap-filled
    /// in the view layer when easier — we just give the raw counts here).
    func fetchDueCountsByDay(daysAhead: Int = 7, inBook bookId: String? = nil, now: Date = Date()) throws -> [(date: Date, count: Int)] {
        try dbQueue.read { db in
            // SQLite stores ISO-8601 from GRDB; group by date(dueDate, 'localtime') gives YYYY-MM-DD
            var args: [DatabaseValueConvertible] = []
            var join = ""
            if let bookId {
                join = "INNER JOIN wordListEntry wle ON wle.wordId = rc.wordId AND wle.listId = ?"
                args.append(bookId)
            }
            let cal = Calendar.current
            let startOfToday = cal.startOfDay(for: now)
            guard let endDate = cal.date(byAdding: .day, value: daysAhead, to: startOfToday) else {
                return []
            }
            args.append(startOfToday)
            args.append(endDate)
            let sql = """
                SELECT date(rc.dueDate, 'localtime') AS day, COUNT(*) AS cnt
                FROM reviewCard rc
                \(join)
                WHERE rc.state != 0 AND rc.dueDate >= ? AND rc.dueDate < ?
                GROUP BY day
                ORDER BY day
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))

            // Map sparse SQL results into a dense 7-day array
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            var counts: [String: Int] = [:]
            for row in rows {
                if let day: String = row["day"], let cnt: Int = row["cnt"] {
                    counts[day] = cnt
                }
            }
            var result: [(Date, Int)] = []
            for offset in 0..<daysAhead {
                guard let day = cal.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
                let key = formatter.string(from: day)
                result.append((day, counts[key] ?? 0))
            }
            return result
        }
    }

    /// Group due-now cards into time buckets for the Plan due-backlog section.
    /// "Today" = due before tomorrow; "Tomorrow"; "ThisWeek" = days 2..6; "Later" = day 7+
    /// (only past-due and within-7-days are returned to keep the section bounded).
    enum DueBucket: String, CaseIterable {
        case overdue        // before today
        case today          // due before tomorrow
        case tomorrow
        case thisWeek       // remaining of this week (days 2..6)
        case later          // day 7+ (capped to 30 for sanity)

        var label: String {
            switch self {
            case .overdue: "Overdue"
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .thisWeek: "This week"
            case .later: "Later"
            }
        }
    }

    func fetchDueBacklog(inBook bookId: String? = nil, now: Date = Date(), perBucketLimit: Int = 100) throws -> [DueBucket: [WordSummary]] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        guard
            let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday),
            let startOfDay2 = cal.date(byAdding: .day, value: 2, to: startOfToday),
            let startOfDay7 = cal.date(byAdding: .day, value: 7, to: startOfToday),
            let startOfDay30 = cal.date(byAdding: .day, value: 30, to: startOfToday)
        else {
            return [:]
        }

        return try dbQueue.read { db in
            var result: [DueBucket: [WordSummary]] = [:]
            let buckets: [(DueBucket, Date, Date)] = [
                (.overdue, .distantPast, startOfToday),
                (.today, startOfToday, startOfTomorrow),
                (.tomorrow, startOfTomorrow, startOfDay2),
                (.thisWeek, startOfDay2, startOfDay7),
                (.later, startOfDay7, startOfDay30),
            ]
            for (bucket, start, end) in buckets {
                var args: [DatabaseValueConvertible] = []
                var from = "FROM word w INNER JOIN reviewCard rc ON rc.wordId = w.id"
                if let bookId {
                    from += " INNER JOIN wordListEntry wle ON wle.wordId = w.id AND wle.listId = ?"
                    args.append(bookId)
                }
                let sql = """
                    SELECT
                      w.id AS id,
                      w.spelling AS spelling,
                      w.phonetic AS phonetic,
                      w.frequency AS frequency,
                      json_extract(w.data, '$.definitions[0].chinese') AS firstDefZh,
                      json_extract(w.data, '$.definitions[0].partOfSpeech') AS posLabel,
                      CASE
                        WHEN json_extract(w.data, '$.mnemonics') IS NOT NULL
                          AND json_array_length(json_extract(w.data, '$.mnemonics')) > 0
                        THEN 1 ELSE 0
                      END AS hasMnemonic,
                      rc.state AS cardState
                    \(from)
                    WHERE rc.state != 0 AND rc.dueDate >= ? AND rc.dueDate < ?
                    ORDER BY rc.dueDate ASC
                    LIMIT ?
                    """
                args.append(start)
                args.append(end)
                args.append(perBucketLimit)
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                let summaries = rows.map(Self.rowToSummary)
                if !summaries.isEmpty {
                    result[bucket] = summaries
                }
            }
            return result
        }
    }

    /// Count due cards in each bucket (for showing totals in the UI without loading all words).
    func fetchDueBacklogCounts(inBook bookId: String? = nil, now: Date = Date()) throws -> [DueBucket: Int] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        guard
            let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday),
            let startOfDay2 = cal.date(byAdding: .day, value: 2, to: startOfToday),
            let startOfDay7 = cal.date(byAdding: .day, value: 7, to: startOfToday),
            let startOfDay30 = cal.date(byAdding: .day, value: 30, to: startOfToday)
        else {
            return [:]
        }

        return try dbQueue.read { db in
            var counts: [DueBucket: Int] = [:]
            let buckets: [(DueBucket, Date, Date)] = [
                (.overdue, .distantPast, startOfToday),
                (.today, startOfToday, startOfTomorrow),
                (.tomorrow, startOfTomorrow, startOfDay2),
                (.thisWeek, startOfDay2, startOfDay7),
                (.later, startOfDay7, startOfDay30),
            ]
            for (bucket, start, end) in buckets {
                var args: [DatabaseValueConvertible] = []
                var join = ""
                if let bookId {
                    join = "INNER JOIN wordListEntry wle ON wle.wordId = rc.wordId AND wle.listId = ?"
                    args.append(bookId)
                }
                args.append(start)
                args.append(end)
                let sql = """
                    SELECT COUNT(*) FROM reviewCard rc
                    \(join)
                    WHERE rc.state != 0 AND rc.dueDate >= ? AND rc.dueDate < ?
                    """
                let cnt = try Int.fetchOne(db, sql: sql, arguments: StatementArguments(args)) ?? 0
                if cnt > 0 { counts[bucket] = cnt }
            }
            return counts
        }
    }

    /// Shared row → WordSummary mapping helper.
    /// `dueDate` is optional in the SELECT — callers that don't need it can omit
    /// the column and we'll just leave it nil.
    ///
    /// IMPORTANT: GRDB returns SQLite integers as `Int64`. Using `row["x"] as? Int`
    /// goes through `DatabaseValue` and silently fails (returns nil) for many
    /// values. Use the typed annotation form `let x: Int? = row["x"]` instead —
    /// GRDB's typed subscript handles the Int64 → Int conversion correctly.
    /// This was the cause of the "all rows show as New" bug in Library when
    /// filtering by Review state: SQL was returning state=2 but Swift was
    /// reading nil → falling back to .new on the badge.
    private static func rowToSummary(_ row: Row) -> WordSummary {
        let frequencyRaw: Int? = row["frequency"]
        let frequency = FrequencyTier(rawValue: frequencyRaw ?? FrequencyTier.common.rawValue) ?? .common
        let stateRaw: Int? = row["cardState"]
        let cardState = stateRaw.flatMap { CardState(rawValue: $0) }
        let dueDate: Date? = row["dueDate"]
        let hasMnemonicRaw: Int? = row["hasMnemonic"]
        return WordSummary(
            id: row["id"],
            spelling: row["spelling"],
            phonetic: row["phonetic"],
            frequency: frequency,
            firstDefZh: row["firstDefZh"],
            posLabel: row["posLabel"],
            hasMnemonic: (hasMnemonicRaw ?? 0) == 1,
            cardState: cardState,
            dueDate: dueDate
        )
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

    // MARK: - Meta (key-value)
    //
    // Tiny key/value store. Currently used for `wordsVersion` (the version
    // string of the bundled words.json that last seeded the DB). When the
    // bundled version is newer than what's stored, WordLoader runs an upgrade
    // pass that overwrites word.data — reviewCard / reviewLog / user_content
    // are untouched, so FSRS progress and user mnemonics survive.

    func metaValue(forKey key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM meta WHERE key = ?",
                arguments: [key]
            )
        }
    }

    func setMetaValue(_ value: String, forKey key: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }

    // MARK: - User Content (mnemonics, notes, ...)

    /// User-authored content row stored in `user_content`.
    struct UserContent: Identifiable, Hashable {
        let id: Int64
        let wordId: String
        let type: String         // "mnemonic" | "note" | future
        let content: String
        let createdAt: Date
        let updatedAt: Date
    }

    func addUserContent(wordId: String, type: String, content: String) throws -> Int64 {
        try dbQueue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO user_content (wordId, type, content, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [wordId, type, content, now, now]
            )
            return db.lastInsertedRowID
        }
    }

    func updateUserContent(id: Int64, content: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE user_content SET content = ?, updatedAt = ? WHERE id = ?",
                arguments: [content, Date(), id]
            )
        }
    }

    func deleteUserContent(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM user_content WHERE id = ?", arguments: [id])
        }
    }

    func fetchUserContent(wordId: String, type: String? = nil) throws -> [UserContent] {
        try dbQueue.read { db in
            let sql: String
            let args: StatementArguments
            if let type {
                sql = """
                    SELECT id, wordId, type, content, createdAt, updatedAt
                    FROM user_content WHERE wordId = ? AND type = ?
                    ORDER BY createdAt DESC
                    """
                args = [wordId, type]
            } else {
                sql = """
                    SELECT id, wordId, type, content, createdAt, updatedAt
                    FROM user_content WHERE wordId = ?
                    ORDER BY createdAt DESC
                    """
                args = [wordId]
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.map { row in
                UserContent(
                    id: row["id"],
                    wordId: row["wordId"],
                    type: row["type"],
                    content: row["content"],
                    createdAt: row["createdAt"],
                    updatedAt: row["updatedAt"]
                )
            }
        }
    }

    // MARK: - Word-centric queries (for WordDetailView)

    /// The (single) review card for a word, or nil if none has been created.
    func fetchReviewCard(forWord wordId: String) throws -> ReviewCard? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM reviewCard WHERE wordId = ? LIMIT 1",
                arguments: [wordId]
            ) else { return nil }
            return self.rowToCard(row)
        }
    }

    /// Recent review logs for a card, newest first.
    func fetchReviewLogs(cardId: UUID, limit: Int = 10) throws -> [ReviewLog] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM reviewLog WHERE cardId = ?
                    ORDER BY timestamp DESC LIMIT ?
                    """,
                arguments: [cardId.uuidString, limit]
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

    /// Word books that contain this word.
    func fetchBooks(containingWord wordId: String) throws -> [WordBook] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT wl.*, COUNT(wle2.wordId) as wordCount
                FROM wordList wl
                INNER JOIN wordListEntry wle ON wle.listId = wl.id AND wle.wordId = ?
                LEFT JOIN wordListEntry wle2 ON wle2.listId = wl.id
                GROUP BY wl.id
                ORDER BY wl.name
                """, arguments: [wordId])
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
