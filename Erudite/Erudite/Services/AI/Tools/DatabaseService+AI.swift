import Foundation
import GRDB

// MARK: - DatabaseService AI Tool Extensions

/// Query methods used by AI tools to access learning state.
extension DatabaseService {

    // MARK: - Card Lookup

    /// Fetch the review card for a word by its wordId
    func fetchCardForWord(wordId: String) throws -> ReviewCard? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM reviewCard WHERE wordId = ?",
                arguments: [wordId]
            ) else {
                return nil
            }
            return Self.cardFromRow(row)
        }
    }

    /// Fetch review logs for a specific card, most recent first
    func fetchReviewLogsForCard(cardId: UUID) throws -> [ReviewLog] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM reviewLog WHERE cardId = ? ORDER BY timestamp DESC",
                arguments: [cardId.uuidString]
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

    // MARK: - Weak Words

    /// Fetch the weakest cards (highest lapses or lowest stability)
    func fetchWeakCards(limit: Int, sortBy: String, inBook bookId: String? = nil) throws -> [(word: Word, card: ReviewCard)] {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            let orderClause = sortBy == "stability"
                ? "rc.stability ASC"
                : "rc.lapses DESC"

            let sql: String
            let args: StatementArguments
            if let bookId {
                sql = """
                    SELECT w.data, rc.*
                    FROM reviewCard rc
                    JOIN word w ON w.id = rc.wordId
                    JOIN wordListEntry wle ON wle.wordId = rc.wordId
                    WHERE wle.listId = ? AND rc.state != 0 AND rc.lapses > 0
                    ORDER BY \(orderClause)
                    LIMIT ?
                    """
                args = [bookId, limit]
            } else {
                sql = """
                    SELECT w.data, rc.*
                    FROM reviewCard rc
                    JOIN word w ON w.id = rc.wordId
                    WHERE rc.state != 0 AND rc.lapses > 0
                    ORDER BY \(orderClause)
                    LIMIT ?
                    """
                args = [limit]
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.compactMap { row -> (Word, ReviewCard)? in
                guard let data = row["data"] as? Data,
                      let word = try? decoder.decode(Word.self, from: data) else {
                    return nil
                }
                let card = Self.cardFromRow(row)
                return (word, card)
            }
        }
    }

    // MARK: - Statistics

    /// Calculate recent accuracy (last 7 days)
    func fetchRecentAccuracy() throws -> Double {
        try dbQueue.read { db in
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT
                        COUNT(*) as total,
                        SUM(CASE WHEN rating >= 3 THEN 1 ELSE 0 END) as correct
                    FROM reviewLog
                    WHERE timestamp >= ?
                    """,
                arguments: [sevenDaysAgo]
            )
            guard let row,
                  let total = row["total"] as? Int, total > 0,
                  let correct = row["correct"] as? Int else {
                return 0.0
            }
            return Double(correct) / Double(total)
        }
    }

    /// Calculate current study streak (consecutive days with at least 1 review)
    func fetchStudyStreak() throws -> Int {
        try dbQueue.read { db in
            // Get distinct study days, ordered most recent first
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT date(timestamp) as study_date
                    FROM reviewLog
                    ORDER BY study_date DESC
                    LIMIT 90
                    """
            )

            guard !rows.isEmpty else { return 0 }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            var streak = 0
            var expectedDate = today

            for row in rows {
                guard let dateStr = row["study_date"] as? String else { continue }
                // Parse YYYY-MM-DD
                let components = dateStr.split(separator: "-")
                guard components.count == 3,
                      let year = Int(components[0]),
                      let month = Int(components[1]),
                      let day = Int(components[2]) else { continue }

                guard let studyDate = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                    continue
                }

                if calendar.isDate(studyDate, inSameDayAs: expectedDate) {
                    streak += 1
                    expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate)!
                } else if studyDate < expectedDate {
                    // Gap in streak — stop counting
                    break
                }
                // If studyDate > expectedDate, skip (shouldn't happen with DESC order)
            }

            return streak
        }
    }

    // MARK: - Helpers

    /// Convert a Row to ReviewCard (duplicated from private rowToCard to use in extension)
    static func cardFromRow(_ row: Row) -> ReviewCard {
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
