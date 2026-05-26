import Foundation
import Observation

// MARK: - Study View Model

@Observable
final class StudyViewModel {

    // MARK: - State

    enum Phase {
        case loading
        case studying
        case empty      // no cards available
        case complete   // session finished
    }

    var phase: Phase = .loading
    var currentWord: Word?
    var currentCard: ReviewCard?
    var isRevealed: Bool = false
    var schedulingResult: FSRSEngine.SchedulingResult?

    // Session stats
    var cardsStudied: Int = 0
    var cardsRemaining: Int = 0
    var sessionStartTime: Date = Date()

    // MARK: - Dependencies

    private var database: DatabaseService?
    private let engine = FSRSEngine()
    private let pronunciation = PronunciationService()
    private var cardQueue: [ReviewCard] = []
    private var wordCache: [String: Word] = [:]
    private var history: [(card: ReviewCard, word: Word?)] = [] // for go-back

    // MARK: - Public API

    func start(database: DatabaseService, mode: StudyQueueMode = .mixed) {
        self.database = database
        self.sessionStartTime = Date()
        self.cardsStudied = 0
        self.history = []
        pronunciation.clearCache()
        loadQueue(mode: mode)
    }

    func reveal() {
        guard currentCard != nil else { return }
        isRevealed = true
        schedulingResult = engine.schedule(card: currentCard!)
    }

    func rate(_ rating: Rating) {
        guard let card = currentCard,
              let result = schedulingResult,
              let db = database else { return }

        // Get the updated card based on rating
        let updatedCard: ReviewCard = switch rating {
        case .again: result.again
        case .hard: result.hard
        case .good: result.good
        case .easy: result.easy
        }

        // Persist
        do {
            try db.updateCard(updatedCard)
            try db.insertReviewLog(ReviewLog(
                cardId: card.id,
                rating: rating,
                state: card.state,
                elapsedDays: card.elapsedDays,
                scheduledDays: updatedCard.scheduledDays
            ))
        } catch {
            print("Failed to save review: \(error)")
        }

        cardsStudied += 1
        advanceToNext()
    }

    /// Replay pronunciation for current word
    func replayPronunciation() {
        guard let word = currentWord else { return }
        pronunciation.speak(word.spelling)
    }

    /// Skip current card without rating (push to end of queue)
    func skip() {
        guard let card = currentCard else { return }
        // Put it back at the end so it comes up again later
        cardQueue.append(card)
        advanceToNext()
    }

    /// Go back to previous card (view only, no re-rating)
    func goBack() {
        guard let prev = history.popLast() else { return }
        // Save current card back to front of queue
        if let card = currentCard {
            cardQueue.insert(card, at: 0)
        }
        currentCard = prev.card
        currentWord = prev.word
        isRevealed = true  // Show it revealed so user can see the answer
        schedulingResult = nil  // No re-rating allowed
        cardsRemaining = cardQueue.count
        phase = .studying

        if let word = prev.word {
            pronunciation.speak(word.spelling)
        }
    }

    /// End the session early
    func endSession() {
        pronunciation.stop()
        pronunciation.clearCache()
        phase = .complete
    }

    // MARK: - Helpers

    func intervalLabel(for rating: Rating) -> String {
        guard let result = schedulingResult else { return "" }
        return switch rating {
        case .again: result.againInterval
        case .hard: result.hardInterval
        case .good: result.goodInterval
        case .easy: result.easyInterval
        }
    }

    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStartTime)
    }

    // MARK: - Private

    private func loadQueue(mode: StudyQueueMode) {
        guard let db = database else {
            phase = .empty
            return
        }

        do {
            var cards: [ReviewCard] = []

            switch mode {
            case .mixed:
                let due = try db.fetchDueCards()
                let new = try db.fetchNewCards(limit: 10)
                cards = due + new
            case .reviewOnly:
                cards = try db.fetchDueCards()
            case .newOnly:
                cards = try db.fetchNewCards(limit: 20)
            }

            guard !cards.isEmpty else {
                phase = .empty
                return
            }

            cardQueue = cards
            cardsRemaining = cards.count

            // Prefetch words
            let wordIds = cards.map(\.wordId)
            wordCache = try db.fetchWords(ids: wordIds)

            advanceToNext()
        } catch {
            print("Failed to load study queue: \(error)")
            phase = .empty
        }
    }

    private func advanceToNext() {
        // Push current to history (for go-back)
        if let card = currentCard {
            history.append((card: card, word: currentWord))
        }

        guard !cardQueue.isEmpty else {
            pronunciation.stop()
            phase = .complete
            return
        }

        let card = cardQueue.removeFirst()
        currentCard = card
        currentWord = wordCache[card.wordId]
        isRevealed = false
        schedulingResult = nil
        cardsRemaining = cardQueue.count
        phase = .studying

        // Auto-pronounce the new word
        if let word = currentWord {
            pronunciation.speak(word.spelling)

            // Prefetch next word's audio
            if let nextCard = cardQueue.first,
               let nextWord = wordCache[nextCard.wordId] {
                pronunciation.prefetch(nextWord.spelling)
            }
        }
    }
}

// MARK: - Study Queue Mode

enum StudyQueueMode {
    case mixed      // new + due
    case reviewOnly // due cards only
    case newOnly    // new cards only
}
