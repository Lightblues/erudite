import Foundation

// MARK: - StudySession

struct StudySession: Identifiable, Codable, Hashable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    let mode: StudyMode
    var wordsStudied: Int
    var wordsNew: Int
    var wordsReviewed: Int
    var accuracy: Double?
    var aiSummary: String?

    init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = nil,
        mode: StudyMode,
        wordsStudied: Int = 0,
        wordsNew: Int = 0,
        wordsReviewed: Int = 0,
        accuracy: Double? = nil,
        aiSummary: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.mode = mode
        self.wordsStudied = wordsStudied
        self.wordsNew = wordsNew
        self.wordsReviewed = wordsReviewed
        self.accuracy = accuracy
        self.aiSummary = aiSummary
    }
}

enum StudyMode: String, Codable, Hashable {
    case fsrsLearn
    case flashcard
    case quizWordToDef
    case quizDefToWord
    case quizSEPairing
    case speedReview

    var label: String {
        switch self {
        case .fsrsLearn: "Learn"
        case .flashcard: "Flashcard"
        case .quizWordToDef: "Quiz: Word → Def"
        case .quizDefToWord: "Quiz: Def → Word"
        case .quizSEPairing: "SE Pairing"
        case .speedReview: "Speed Review"
        }
    }
}
