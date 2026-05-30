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
    let cardState: CardState?   // nil if no ReviewCard exists yet

    init(
        id: String,
        spelling: String,
        phonetic: String? = nil,
        frequency: FrequencyTier,
        firstDefZh: String? = nil,
        posLabel: String? = nil,
        hasMnemonic: Bool = false,
        cardState: CardState? = nil
    ) {
        self.id = id
        self.spelling = spelling
        self.phonetic = phonetic
        self.frequency = frequency
        self.firstDefZh = firstDefZh
        self.posLabel = posLabel
        self.hasMnemonic = hasMnemonic
        self.cardState = cardState
    }
}

// MARK: - Sort

nonisolated enum WordSort: String, CaseIterable, Hashable {
    case frequency      // by tier then alphabetical (default)
    case alphabetical
    case dueDate        // soonest due first (review cards)
    case lapses         // most lapses first

    var label: String {
        switch self {
        case .frequency: "Frequency"
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
