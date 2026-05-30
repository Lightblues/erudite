import Foundation
import Observation

// MARK: - Study View Model

@Observable
final class StudyViewModel {

    // MARK: - Types

    enum Phase {
        case loading
        case idle           // paused — press Space to resume
        case studying
        case unitComplete   // finished a unit (10–15 cards) — show summary, await Continue/Stop
        case empty          // no cards available
        case complete       // session finished (queue exhausted or user stopped)
    }

    // MARK: - State

    var phase: Phase = .loading
    var currentWord: Word?
    var currentCard: ReviewCard?
    var isRevealed: Bool = false
    var schedulingResult: FSRSEngine.SchedulingResult?

    // Session stats (whole session, across units)
    var cardsStudied: Int = 0
    var cardsRemaining: Int = 0
    var sessionStartTime: Date = Date()

    // Session results for summary
    var reviewResults: [(word: Word, rating: Rating)] = []

    // MARK: - Unit chunking
    //
    // The user sees the session in "units" of `unitSize` cards. Hitting the
    // unit boundary transitions to `.unitComplete` and we show a summary
    // card; pressing Continue (Space/Return) starts the next unit. The unit
    // is purely a UX layer — FSRS scheduling never sees it. Defaults to 12,
    // which fits about 5–7 minutes of study per unit (the empirical sweet
    // spot for "feel of progress" without giving up).

    var unitSize: Int {
        didSet {
            UserDefaults.standard.set(unitSize, forKey: "study_unitSize")
        }
    }
    /// 1-based count of completed units in this session.
    var unitsCompleted: Int = 0
    /// Cards rated since the start of the current unit. Resets to 0 when we
    /// transition past `.unitComplete` back to `.studying`.
    var cardsThisUnit: Int = 0
    /// Word/rating pairs collected within the current unit, used by the
    /// unit-complete summary card. Cleared at the start of each unit.
    var unitResults: [(word: Word, rating: Rating)] = []
    /// Time the current unit started — drives the "took X seconds" line on
    /// the summary card.
    var unitStartTime: Date = Date()

    // MARK: - Settings (persisted, shared with Typing)

    var accent: TypingViewModel.Accent {
        didSet {
            UserDefaults.standard.set(accent.rawValue, forKey: "typing_accent")
            pronunciation.voice = accent == .us ? PronunciationService.Voice.us : PronunciationService.Voice.uk
        }
    }

    var loopPronunciation: Bool {
        didSet {
            UserDefaults.standard.set(loopPronunciation, forKey: "typing_loopPronunciation")
        }
    }

    // MARK: - Word list access (for popover)

    var queueWords: [(word: Word, card: ReviewCard)] {
        cardQueue.compactMap { card in
            guard let word = wordCache[card.wordId] else { return nil }
            return (word: word, card: card)
        }
    }

    /// Previous word (from history)
    var previousWord: Word? {
        guard let last = history.last else { return nil }
        return last.word
    }

    /// Next word in queue
    var nextWord: Word? {
        guard let nextCard = cardQueue.first else { return nil }
        return wordCache[nextCard.wordId]
    }

    // MARK: - Dependencies

    private var database: DatabaseService?
    private let engine = FSRSEngine()
    private let pronunciation = PronunciationService()
    private var cardQueue: [ReviewCard] = []
    private(set) var wordCache: [String: Word] = [:]
    private var history: [(card: ReviewCard, word: Word?)] = [] // for go-back
    private var bookId: String? = nil
    private var loopTimer: Timer?

    // MARK: - Init

    init() {
        self.accent = TypingViewModel.Accent(rawValue: UserDefaults.standard.string(forKey: "typing_accent") ?? "") ?? .us
        self.loopPronunciation = UserDefaults.standard.bool(forKey: "typing_loopPronunciation")
        let storedUnitSize = UserDefaults.standard.integer(forKey: "study_unitSize")
        self.unitSize = storedUnitSize > 0 ? storedUnitSize : 12
        self.pronunciation.voice = accent == .us ? PronunciationService.Voice.us : PronunciationService.Voice.uk
    }

    // MARK: - Public API

    func start(database: DatabaseService, mode: StudyQueueMode = .mixed, bookId: String? = nil) {
        self.database = database
        self.bookId = bookId
        self.sessionStartTime = Date()
        self.cardsStudied = 0
        self.history = []
        self.reviewResults = []
        self.unitsCompleted = 0
        self.cardsThisUnit = 0
        self.unitResults = []
        self.unitStartTime = Date()
        pronunciation.voice = accent == .us ? PronunciationService.Voice.us : PronunciationService.Voice.uk
        pronunciation.clearCache()
        loadQueue(mode: mode)
    }

    /// Pause session (Esc key)
    func deactivate() {
        guard phase == .studying else { return }
        stopLoop()
        phase = .idle
    }

    /// Resume from pause
    func activate() {
        guard phase == .idle else { return }
        phase = .studying
        if let word = currentWord {
            pronunciation.speak(word.spelling)
            startLoopIfNeeded()
        }
    }

    func reveal() {
        guard currentCard != nil else { return }
        isRevealed = true
        schedulingResult = engine.schedule(card: currentCard!)
    }

    /// Toggle card reveal state (space key)
    func toggleReveal() {
        if isRevealed {
            isRevealed = false
        } else {
            reveal()
        }
    }

    func rate(_ rating: Rating) {
        guard let card = currentCard, let db = database else { return }

        // For Easy without reveal, ensure we have scheduling result
        if schedulingResult == nil {
            schedulingResult = engine.schedule(card: card)
        }
        guard let result = schedulingResult else { return }

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
        cardsThisUnit += 1
        if let word = currentWord {
            reviewResults.append((word: word, rating: rating))
            unitResults.append((word: word, rating: rating))
        }

        // If queue is empty, run the normal advance which transitions to
        // .complete; otherwise check for unit boundary first so the unit
        // summary card always shows before the queue is exhausted.
        if cardsThisUnit >= unitSize && !cardQueue.isEmpty {
            // Push current to history (advanceToNext does this; we need it
            // here too so go-back works after pressing Continue).
            if let card = currentCard {
                history.append((card: card, word: currentWord))
            }
            stopLoop()
            pronunciation.stop()
            unitsCompleted += 1
            phase = .unitComplete
            return
        }
        advanceToNext()
    }

    /// Called when the user presses Continue on the unit summary card. Resets
    /// the per-unit counters and pulls the next card from the queue.
    func continueAfterUnit() {
        guard phase == .unitComplete else { return }
        cardsThisUnit = 0
        unitResults = []
        unitStartTime = Date()
        phase = .studying
        // We already pushed the previous card to history in rate(); here we
        // just want the next card without double-pushing, so manually drive
        // the same path as advanceToNext but skip the history append.
        guard !cardQueue.isEmpty else {
            phase = .complete
            return
        }
        let card = cardQueue.removeFirst()
        currentCard = card
        currentWord = wordCache[card.wordId]
        isRevealed = false
        schedulingResult = nil
        cardsRemaining = cardQueue.count
        if let word = currentWord {
            pronunciation.speak(word.spelling)
            startLoopIfNeeded()
            if let nextCard = cardQueue.first,
               let nextWord = wordCache[nextCard.wordId] {
                pronunciation.prefetch(nextWord.spelling)
            }
        }
    }

    /// Convenience: time spent on the unit just finished. Used by the
    /// unit-summary view.
    var unitDuration: TimeInterval {
        Date().timeIntervalSince(unitStartTime)
    }

    /// Replay pronunciation for current word
    func replayPronunciation() {
        guard let word = currentWord else { return }
        pronunciation.speak(word.spelling)
    }

    /// Toggle loop pronunciation
    func toggleLoopPronunciation() {
        loopPronunciation.toggle()
        if loopPronunciation && phase == .studying {
            startLoopIfNeeded()
        } else {
            stopLoop()
        }
    }

    /// Skip current card without rating (just move to next, don't re-queue)
    func skip() {
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

    /// Jump to a specific word in the queue
    func goToWord(at index: Int) {
        guard index >= 0, index < cardQueue.count else { return }
        let card = cardQueue.remove(at: index)
        // Save current card back to queue
        if let current = currentCard {
            cardQueue.insert(current, at: index)
        }
        currentCard = card
        currentWord = wordCache[card.wordId]
        isRevealed = false
        schedulingResult = nil
        cardsRemaining = cardQueue.count

        if let word = currentWord {
            pronunciation.speak(word.spelling)
            startLoopIfNeeded()
        }
    }

    /// End the session early
    func endSession() {
        stopLoop()
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
                let due = try db.fetchDueCards(inBook: bookId)
                let new = try db.fetchNewCards(limit: 10, inBook: bookId)
                cards = due + new
            case .reviewOnly:
                cards = try db.fetchDueCards(inBook: bookId)
            case .newOnly:
                cards = try db.fetchNewCards(limit: 20, inBook: bookId)
            }

            // Deduplicate by wordId (keep first occurrence)
            var seenWordIds: Set<String> = []
            cards = cards.filter { card in
                if seenWordIds.contains(card.wordId) { return false }
                seenWordIds.insert(card.wordId)
                return true
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
            stopLoop()
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
            startLoopIfNeeded()

            // Prefetch next word's audio
            if let nextCard = cardQueue.first,
               let nextWord = wordCache[nextCard.wordId] {
                pronunciation.prefetch(nextWord.spelling)
            }
        }
    }

    private func startLoopIfNeeded() {
        stopLoop()
        guard loopPronunciation, let word = currentWord else { return }
        loopTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .studying else {
                self?.stopLoop()
                return
            }
            self.pronunciation.speak(word.spelling)
        }
    }

    private func stopLoop() {
        loopTimer?.invalidate()
        loopTimer = nil
    }
}

// MARK: - Study Queue Mode

enum StudyQueueMode {
    case mixed      // new + due
    case reviewOnly // due cards only
    case newOnly    // new cards only
}
