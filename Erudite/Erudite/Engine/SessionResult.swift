import Foundation

// MARK: - SessionResult
//
// Unified shape for "this study session is over, here's what happened",
// shared across:
//
// - Flashcard `.complete` (was: bespoke layout w/ Cards/Duration/Again)
// - Flashcard `.unitComplete` (was: bespoke compact card mid-session)
// - Typing `.chapterComplete` (was: bespoke layout w/ WPM/accuracy)
//
// Each entry can carry both a Flashcard rating (for sessions that went
// through the FSRS reveal cycle) and typing mistakes (for sessions
// driven by typing). When both are present, it means a single word
// was both rated and typed in the same session — we show whichever
// signal is more pressing.

nonisolated struct SessionResult: Sendable {
    let mode: Mode
    let unit: StudyUnit?
    let entries: [Entry]
    let durationSeconds: TimeInterval
    /// Optional mode-specific stats. Typing sets `wpm`; Flashcard
    /// leaves it nil. Future: any post-hoc analytics goes here.
    let wpm: Double?

    enum Mode: Sendable, Hashable {
        case flashcard
        case typing

        var label: String {
            switch self {
            case .flashcard: "Flashcard"
            case .typing: "Typing"
            }
        }

        var icon: String {
            switch self {
            case .flashcard: "rectangle.on.rectangle"
            case .typing: "keyboard"
            }
        }
    }

    struct Entry: Sendable {
        let word: Word
        /// Flashcard rating if this word went through reveal+rate.
        let rating: Rating?
        /// Total typing mistakes across this session for this word.
        /// 0 if not typed.
        let mistakes: Int
        /// How many times this word was touched (rated or typed).
        let attempts: Int

        /// "Worst-first" sort key — same idea as RecapEntry.pressingScore.
        var pressingScore: Int {
            if rating == .again { return 0 }
            if rating == nil && mistakes >= 3 { return 5 }
            if rating == .hard { return 10 }
            if rating == nil && mistakes > 0 { return 15 }
            if rating == .good { return 20 }
            if rating == .easy { return 25 }
            return 30
        }
    }

    // MARK: - Aggregates

    var totalCards: Int { entries.count }

    /// Number of entries with rating == .again or (typing-only) ≥3 mistakes.
    var againCount: Int {
        entries.filter { $0.rating == .again || ($0.rating == nil && $0.mistakes >= 3) }.count
    }

    /// Fraction "got it right". Counts Good/Easy and 0-mistake typing as
    /// success; Again and many-mistakes as failure; Hard and 1-2 mistakes
    /// as half-credit so the user gets a meaningful middle band.
    var accuracy: Double {
        guard !entries.isEmpty else { return 0 }
        let scored: Double = entries.reduce(0) { acc, e in
            if e.rating == .again { return acc + 0 }
            if e.rating == .hard { return acc + 0.5 }
            if e.rating == .good || e.rating == .easy { return acc + 1 }
            // Typing-only
            if e.rating == nil {
                if e.mistakes == 0 { return acc + 1 }
                if e.mistakes <= 2 { return acc + 0.5 }
                return acc + 0
            }
            return acc
        }
        return scored / Double(entries.count)
    }

    /// Sorted "worst first" so the user's eye lands on what to revisit.
    var sortedEntries: [Entry] {
        entries.sorted { a, b in
            if a.pressingScore != b.pressingScore { return a.pressingScore < b.pressingScore }
            return a.word.spelling.lowercased() < b.word.spelling.lowercased()
        }
    }
}
