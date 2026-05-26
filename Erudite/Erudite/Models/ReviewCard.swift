import Foundation

// MARK: - ReviewCard (FSRS State)

struct ReviewCard: Identifiable, Codable, Hashable {
    let id: UUID
    let wordId: String

    // FSRS parameters
    var stability: Double
    var difficulty: Double
    var elapsedDays: Int
    var scheduledDays: Int
    var reps: Int
    var lapses: Int
    var state: CardState
    var dueDate: Date
    var lastReview: Date?

    init(
        id: UUID = UUID(),
        wordId: String,
        stability: Double = 0,
        difficulty: Double = 5.0,
        elapsedDays: Int = 0,
        scheduledDays: Int = 0,
        reps: Int = 0,
        lapses: Int = 0,
        state: CardState = .new,
        dueDate: Date = Date(),
        lastReview: Date? = nil
    ) {
        self.id = id
        self.wordId = wordId
        self.stability = stability
        self.difficulty = difficulty
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.reps = reps
        self.lapses = lapses
        self.state = state
        self.dueDate = dueDate
        self.lastReview = lastReview
    }
}

// MARK: - CardState

enum CardState: Int, Codable, Hashable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3

    var label: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .review: "Review"
        case .relearning: "Relearning"
        }
    }
}

// MARK: - Rating

enum Rating: Int, Codable, Hashable, CaseIterable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    var icon: String {
        switch self {
        case .again: "xmark.circle"
        case .hard: "face.dashed"
        case .good: "checkmark.circle"
        case .easy: "bolt.circle"
        }
    }
}

// MARK: - ReviewLog

struct ReviewLog: Codable, Hashable, Identifiable {
    let id: Int?
    let cardId: UUID
    let rating: Rating
    let state: CardState
    let timestamp: Date
    let elapsedDays: Int
    let scheduledDays: Int
    let reviewDuration: TimeInterval?

    init(
        id: Int? = nil,
        cardId: UUID,
        rating: Rating,
        state: CardState,
        timestamp: Date = Date(),
        elapsedDays: Int = 0,
        scheduledDays: Int = 0,
        reviewDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.cardId = cardId
        self.rating = rating
        self.state = state
        self.timestamp = timestamp
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.reviewDuration = reviewDuration
    }
}
