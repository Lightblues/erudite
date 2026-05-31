import Foundation

// MARK: - StudyUnit
//
// Domain object representing one chunk of a study session. Replaces the
// previous "split the queue every N reviews" approach with a real, named,
// resumable thing.
//
// A StudyUnit:
// - is built up-front by StudyQueueBuilder (cards + words + meta resolved
//   when the user picks the unit, not as they study)
// - is consumed by either StudyViewModel (Flashcard) or TypingViewModel
//   (Typing) — same data, different interaction
// - knows its own size, kind, and a human-readable title for the
//   pre-study preview screen
// - emits FSRS feedback in both flashcard and (gated) typing modes so
//   the two paths converge on the same scheduling state
//
// `kind` distinguishes the user-facing flavor; the queue builder uses it
// to decide which cards to include and in what order.

nonisolated struct StudyUnit: Identifiable, Sendable {
    let id: UUID
    let kind: Kind
    /// Resolved review cards in the order they should be presented.
    let cards: [ReviewCard]
    /// wordId → Word, prefetched so list views and StudyView never
    /// re-query inside the loop.
    let words: [String: Word]
    /// "Reviews", "New words", "GRE 3000 · Unit 5", ...
    let title: String
    /// "12 cards · ~5 min", populated by the builder.
    let subtitle: String
    /// Rough minute estimate used for the Today list. ~25s per card is
    /// the empirical average across mixed sessions; tweak after we have
    /// real telemetry.
    let estimatedMinutes: Int

    enum Kind: Sendable, Hashable {
        case reviews                                    // pure due cards
        case newWords                                   // pure new (state=0)
        case mix                                        // reviews + new
        case bookChapter(bookId: String, index: Int)    // book unit N
        /// User-driven re-practice of words touched today. Unlike all
        /// other kinds, ratings collected during a `.recap` session do
        /// NOT write back to FSRS — this is "演练模式". The session is
        /// tracked in SessionResult/SessionSummary so the user still
        /// gets feedback, but reviewCard.dueDate isn't bumped.
        case recap

        var icon: String {
            switch self {
            case .reviews: "arrow.clockwise.circle.fill"
            case .newWords: "plus.circle.fill"
            case .mix: "shuffle.circle.fill"
            case .bookChapter: "book.closed.fill"
            case .recap: "arrow.uturn.left.circle.fill"
            }
        }

        var color: ColorName {
            switch self {
            case .reviews: .orange
            case .newWords: .blue
            case .mix: .purple
            case .bookChapter: .indigo
            case .recap: .pink
            }
        }

        /// True iff ratings/typing during this unit should NOT update
        /// the FSRS schedule. Currently only `.recap` opts out — the
        /// user is practicing, not committing.
        var skipsFSRSWriteback: Bool {
            switch self {
            case .recap: true
            default: false
            }
        }
    }

    /// Plain enum so the model layer doesn't import SwiftUI. View code
    /// maps this to a Color.
    enum ColorName: Sendable, Hashable {
        case orange, blue, purple, indigo, pink
    }

    /// Words in presentation order — used by UnitPreviewView's scan-read list.
    var orderedWords: [Word] {
        cards.compactMap { words[$0.wordId] }
    }
}
