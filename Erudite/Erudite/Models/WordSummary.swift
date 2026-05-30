import Foundation

// MARK: - WordSummary
//
// Lightweight projection of a Word + its ReviewCard state, used by list views
// (Library, Today preview, Plan queue) to avoid decoding the full Word JSON
// for every row.
//
// Always read-only and derived from the database. Never persisted directly.

nonisolated struct WordSummary: Identifiable, Hashable {
    let id: String              // wordId
    let spelling: String
    let phonetic: String?
    let frequency: FrequencyTier
    let firstDefZh: String?     // first Chinese definition (for list display)
    let posLabel: String?       // first part-of-speech ("adj", "v", ...)
    let hasMnemonic: Bool       // any builtin mnemonic available
    /// True iff `user_content` has a row with type='mnemonic' for this word.
    /// Drives the small purple lightbulb on list rows. After v3.0,
    /// `hasMnemonic` (builtin) is true for ~100% of rows so it has no
    /// discrimination value as a list signal — `hasUserMnemonic` highlights
    /// words the user has actually annotated.
    let hasUserMnemonic: Bool
    let cardState: CardState?   // nil if no ReviewCard exists yet
    let dueDate: Date?          // populated only when the query joins reviewCard
    /// Total reviews (rc.reps). Populated by the standard summary SELECT;
    /// nil only when the row was constructed by hand.
    let reps: Int?
    /// Lapses (rc.lapses) — times the card slipped back from review.
    let lapses: Int?

    init(
        id: String,
        spelling: String,
        phonetic: String? = nil,
        frequency: FrequencyTier,
        firstDefZh: String? = nil,
        posLabel: String? = nil,
        hasMnemonic: Bool = false,
        hasUserMnemonic: Bool = false,
        cardState: CardState? = nil,
        dueDate: Date? = nil,
        reps: Int? = nil,
        lapses: Int? = nil
    ) {
        self.id = id
        self.spelling = spelling
        self.phonetic = phonetic
        self.frequency = frequency
        self.firstDefZh = firstDefZh
        self.posLabel = posLabel
        self.hasMnemonic = hasMnemonic
        self.hasUserMnemonic = hasUserMnemonic
        self.cardState = cardState
        self.dueDate = dueDate
        self.reps = reps
        self.lapses = lapses
    }
}

// MARK: - Sort

/// Sort options exposed in the Library picker.
///
/// `bookOrder` is only meaningful when a Book is selected (uses
/// wordListEntry.sortOrder to honor the book's curated order — e.g. GRE 3000's
/// chapter-by-chapter sequence). When no Book is picked, the SQL builder
/// silently falls back to alphabetical so it never produces nonsense.
///
/// `frequency` was removed in 2026-05: the bundled tier (1/2/3) was a coarse
/// 524 / 1779 / 10838 split with no authoritative GRE provenance, and 80% of
/// the rows landed in tier 3 — so the sort was effectively alphabetical for
/// the long tail. If we want a real importance signal in the future, plug in
/// a frequency-rank column or a per-book "weight".
nonisolated enum WordSort: String, CaseIterable, Hashable {
    case bookOrder       // wordListEntry.sortOrder (book selected) → alphabetical fallback
    case alphabetical
    case dueDate         // soonest due first (review cards)
    case lapses          // most lapses first

    var label: String {
        switch self {
        case .bookOrder: "Book Order"
        case .alphabetical: "A → Z"
        case .dueDate: "Due Date"
        case .lapses: "Most Lapses"
        }
    }
}

// MARK: - State Filter

/// Filter for review-card state; collapses learning + relearning into a single
/// "Learning" bucket since users don't care about the distinction here.
nonisolated enum WordStateFilter: String, CaseIterable, Hashable {
    case all
    case new            // state = 0 OR no card row
    case learning       // state = 1 OR 3
    case review         // state = 2
    case mature         // state = 2 AND stability >= 21d (rough threshold)

    var label: String {
        switch self {
        case .all: "All"
        case .new: "New"
        case .learning: "Learning"
        case .review: "Review"
        case .mature: "Mature"
        }
    }
}
