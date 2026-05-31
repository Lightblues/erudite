import Foundation

// MARK: - StudyQueueBuilder
//
// Single source of truth for "which cards make up today's study session".
// Today/Plan/Flashcard/Typing all consume StudyUnits produced by this
// builder so we no longer have three slightly-different SQL queries
// drifting apart over time.
//
// Inputs:
//   - bookId (nil = all books)
//   - unitSize (the user's preferred chunk size, persisted in AppSettings)
// Output:
//   - [StudyUnit] in the order the user should consume them today

nonisolated struct StudyQueueBuilder: Sendable {
    let db: DatabaseService

    // MARK: - Today's units (FSRS-driven)

    /// Build the FSRS-driven list of units shown on Today:
    /// 1. Slice all due cards into `unitSize`-card review units.
    /// 2. Append a single "New" unit (state=0 cards in book sortOrder),
    ///    capped at `unitSize`. The user can choose to do it or not —
    ///    new words are always opt-in, never silently mixed into reviews.
    func buildTodayUnits(
        bookId: String?,
        unitSize: Int,
        now: Date = Date()
    ) throws -> [StudyUnit] {
        var units: [StudyUnit] = []

        // ---- Reviews (FSRS due) ----
        let dueCards = try db.fetchDueCards(now: now, inBook: bookId)
        let dueWordIds = dueCards.map(\.wordId)
        let dueWords = try db.fetchWords(ids: dueWordIds)

        // Stable chunking: cards already sorted by dueDate ascending.
        let chunks = dueCards.chunked(into: unitSize)
        for (index, chunk) in chunks.enumerated() {
            let title: String
            if dueCards.count <= unitSize {
                title = "Reviews"
            } else {
                title = "Reviews · \(index + 1)"
            }
            let chunkIds = Set(chunk.map(\.wordId))
            let chunkWords = dueWords.filter { chunkIds.contains($0.key) }
            let est = estimateMinutes(cardCount: chunk.count, hasNew: false)
            units.append(StudyUnit(
                id: UUID(),
                kind: .reviews,
                cards: chunk,
                words: chunkWords,
                title: title,
                subtitle: "\(chunk.count) cards · ~\(est) min",
                estimatedMinutes: est
            ))
        }

        // ---- New words (opt-in standalone unit) ----
        let newCards = try db.fetchNewCards(limit: unitSize, inBook: bookId)
        if !newCards.isEmpty {
            let newWords = try db.fetchWords(ids: newCards.map(\.wordId))
            let est = estimateMinutes(cardCount: newCards.count, hasNew: true)
            units.append(StudyUnit(
                id: UUID(),
                kind: .newWords,
                cards: newCards,
                words: newWords,
                title: "New words",
                subtitle: "\(newCards.count) cards · ~\(est) min",
                estimatedMinutes: est
            ))
        }

        return units
    }

    // MARK: - Book chapter unit

    /// Build a unit for a specific book chapter. `chapterIndex` is 0-based;
    /// `chapterSize` is the user's preferred unit size (defaults match
    /// Today's flashcard unit size for consistency).
    ///
    /// Cards: each word in the chapter range gets its corresponding
    /// reviewCard. For words that somehow lack a card, we synthesize a
    /// fresh `state=.new` card on the fly so the unit can still be
    /// consumed — this is defensive against any data gap.
    func buildChapterUnit(
        bookId: String,
        chapterIndex: Int,
        chapterSize: Int
    ) throws -> StudyUnit? {
        let offset = chapterIndex * chapterSize
        let words = try db.fetchWordsPage(inBook: bookId, offset: offset, limit: chapterSize)
        guard !words.isEmpty else { return nil }

        // Pull the corresponding cards (one round-trip per word — small N,
        // fine; if it ever bites we can add a fetchCards(forWordIds:) batch).
        var cards: [ReviewCard] = []
        for word in words {
            if let c = try db.fetchReviewCard(forWord: word.id) {
                cards.append(c)
            } else {
                cards.append(ReviewCard(wordId: word.id))
            }
        }

        let book = try db.fetchWordBooks().first { $0.id == bookId }
        let title = "\(book?.name ?? "Book") · Unit \(chapterIndex + 1)"
        let est = estimateMinutes(cardCount: cards.count, hasNew: true)
        let wordsDict = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        return StudyUnit(
            id: UUID(),
            kind: .bookChapter(bookId: bookId, index: chapterIndex),
            cards: cards,
            words: wordsDict,
            title: title,
            subtitle: "\(cards.count) words · ~\(est) min",
            estimatedMinutes: est
        )
    }

    // MARK: - Helpers

    /// Empirical: ~25s per card for review, ~30s for new (extra reading).
    private func estimateMinutes(cardCount: Int, hasNew: Bool) -> Int {
        let perCard: Double = hasNew ? 30 : 25
        return max(1, Int((Double(cardCount) * perCard / 60.0).rounded()))
    }
}

// MARK: - Array.chunked

private extension Array {
    /// Split into equal-sized chunks. Last chunk may be smaller. Used by the
    /// review-units slicer so 33 due cards → [12, 12, 9].
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var i = 0
        while i < count {
            result.append(Array(self[i..<Swift.min(i + size, count)]))
            i += size
        }
        return result
    }
}
