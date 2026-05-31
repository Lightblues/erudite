import Foundation
import AppKit
import Observation

// MARK: - Typing Practice ViewModel

@Observable
final class TypingViewModel {

    // MARK: - Types

    enum Phase {
        case loading
        case idle       // waiting for user to start
        case typing     // actively typing
        case chapterComplete
        case empty
    }

    enum LetterState {
        case untyped
        case correct
        case wrong
    }

    enum HideMode: String, CaseIterable {
        case none       // show all letters
        case vowels     // hide vowels
        case consonants // hide consonants
        case random     // random 40% hidden
        case all        // hide all (full dictation)

        var label: String {
            switch self {
            case .none: "Show All"
            case .vowels: "Hide Vowels"
            case .consonants: "Hide Consonants"
            case .random: "Random Hide"
            case .all: "Hide All"
            }
        }

        var icon: String {
            switch self {
            case .none: "eye"
            case .vowels: "eye.trianglebadge.exclamationmark"
            case .consonants: "eye.slash.circle"
            case .random: "dice"
            case .all: "eye.slash"
            }
        }
    }

    enum ErrorMode: String, CaseIterable {
        case retryChar
        case resetWord

        var label: String {
            switch self {
            case .retryChar: "Retry Char"
            case .resetWord: "Reset Word"
            }
        }
    }

    enum WordOrder: String, CaseIterable {
        case sequential
        case shuffle

        var label: String {
            switch self {
            case .sequential: "Sequential"
            case .shuffle: "Shuffle"
            }
        }
    }

    enum Accent: String, CaseIterable {
        case us
        case uk

        var label: String {
            switch self {
            case .us: "US"
            case .uk: "UK"
            }
        }
    }

    // MARK: - Settings (persisted)

    var hideMode: HideMode {
        didSet { UserDefaults.standard.set(hideMode.rawValue, forKey: "typing_hideMode") }
    }
    var errorMode: ErrorMode {
        didSet { UserDefaults.standard.set(errorMode.rawValue, forKey: "typing_errorMode") }
    }
    var loopPronunciation: Bool {
        didSet { UserDefaults.standard.set(loopPronunciation, forKey: "typing_loopPronunciation") }
    }
    var wordOrder: WordOrder {
        didSet { UserDefaults.standard.set(wordOrder.rawValue, forKey: "typing_wordOrder") }
    }
    var accent: Accent {
        didSet {
            UserDefaults.standard.set(accent.rawValue, forKey: "typing_accent")
            pronunciation.voice = accent == .us ? PronunciationService.Voice.us : PronunciationService.Voice.uk
        }
    }

    // Per-word random visibility (for .random hide mode)
    var randomLetterVisible: [Bool] = []

    // MARK: - Published State

    var phase: Phase = .loading
    var showWordCard: Bool = false

    // Chapter state
    var words: [Word] = []
    var currentIndex: Int = 0
    var chapterIndex: Int = 0
    var totalChapters: Int = 0
    var chapterSize: Int = 20

    // Per-word state
    var letterStates: [LetterState] = []
    var cursorPosition: Int = 0
    var isWordComplete: Bool = false
    var wordMistakes: Int = 0

    // Session stats (character-level)
    var totalInputs: Int = 0
    var totalCorrect: Int = 0
    var totalMistakes: Int = 0
    var wordsCompleted: Int = 0
    var accumulatedTime: TimeInterval = 0  // time spent typing (paused excluded)
    var wordStartTime: Date?
    private var activeStartTime: Date?     // when current typing phase started

    // Per-word results for chapter summary
    var wordResults: [(word: Word, mistakes: Int, duration: TimeInterval)] = []

    // MARK: - Computed

    var currentWord: Word? {
        guard currentIndex < words.count else { return nil }
        return words[currentIndex]
    }

    var targetSpelling: String {
        currentWord?.spelling ?? ""
    }

    var previousWord: Word? {
        guard currentIndex > 0 else { return nil }
        return words[currentIndex - 1]
    }

    var nextWord: Word? {
        guard currentIndex + 1 < words.count else { return nil }
        return words[currentIndex + 1]
    }

    var chapterProgress: String {
        "\(wordsCompleted) / \(words.count)"
    }

    var accuracy: Double {
        totalInputs > 0 ? Double(totalCorrect) / Double(totalInputs) : 0
    }

    var elapsedTime: TimeInterval {
        let liveExtra = activeStartTime.map { Date().timeIntervalSince($0) } ?? 0
        return accumulatedTime + liveExtra
    }

    var wpm: Double {
        let minutes = elapsedTime / 60.0
        guard minutes > 0 else { return 0 }
        return Double(totalCorrect) / 5.0 / minutes
    }

    /// Materialize this session as a `SessionResult` for the shared
    /// `SessionSummaryView`. Per word: latest mistakes count + attempt
    /// count. Same shape Flashcard uses, so the layout matches.
    func sessionResult() -> SessionResult {
        var byWord: [String: SessionResult.Entry] = [:]
        for r in wordResults {
            let existing = byWord[r.word.id]
            byWord[r.word.id] = SessionResult.Entry(
                word: r.word,
                rating: nil,
                mistakes: (existing?.mistakes ?? 0) + r.mistakes,
                attempts: (existing?.attempts ?? 0) + 1
            )
        }
        return SessionResult(
            mode: .typing,
            unit: activeUnit,
            entries: Array(byWord.values),
            durationSeconds: elapsedTime,
            wpm: wpm > 0 ? wpm : nil
        )
    }

    // MARK: - Dependencies

    private var database: DatabaseService?
    private var bookId: String?
    private let pronunciation = PronunciationService()
    private var loopTimer: Timer?

    /// True iff the active session was started from a pre-built StudyUnit
    /// (Today → UnitPreview → Typing). In unit mode, word completions
    /// emit derived FSRS ratings (see advance()) and chapter navigation
    /// is disabled — the unit IS the session.
    private(set) var unitMode: Bool = false
    /// The unit being consumed, if any. Cleared when a new session starts.
    private(set) var activeUnit: StudyUnit?
    /// FSRS engine for deriving rating intervals when a typed word
    /// completes in unit mode.
    private let engine = FSRSEngine()

    // Sound effects: pre-loaded for rapid playback
    private let correctSound: NSSound? = {
        let s = NSSound(named: "Tink")
        s?.volume = 0.6
        return s
    }()
    private let wrongSound: NSSound? = {
        let s = NSSound(named: "Basso")
        s?.volume = 0.8
        return s
    }()
    private let completeSound: NSSound? = {
        let s = NSSound(named: "Glass")
        s?.volume = 1.0
        return s
    }()

    private func playCorrect() {
        correctSound?.stop()
        correctSound?.play()
    }
    private func playWrong() {
        wrongSound?.stop()
        wrongSound?.play()
    }
    private func playComplete() {
        completeSound?.stop()
        completeSound?.play()
    }

    // MARK: - Progress persistence key
    private var progressKey: String {
        "typing_chapter_\(bookId ?? "all")"
    }

    // MARK: - Init (load persisted settings)

    init() {
        self.hideMode = HideMode(rawValue: UserDefaults.standard.string(forKey: "typing_hideMode") ?? "") ?? .none
        self.errorMode = ErrorMode(rawValue: UserDefaults.standard.string(forKey: "typing_errorMode") ?? "") ?? .retryChar
        self.loopPronunciation = UserDefaults.standard.bool(forKey: "typing_loopPronunciation")
        self.wordOrder = WordOrder(rawValue: UserDefaults.standard.string(forKey: "typing_wordOrder") ?? "") ?? .sequential
        self.accent = Accent(rawValue: UserDefaults.standard.string(forKey: "typing_accent") ?? "") ?? .us
        self.pronunciation.voice = accent == .us ? PronunciationService.Voice.us : PronunciationService.Voice.uk
    }

    // MARK: - Public API

    /// Standalone entry: load the persisted chapter for `bookId` from
    /// UserDefaults and let the user browse chapters freely. This is the
    /// experience when the user opens the Typing tab directly. No FSRS
    /// feedback is emitted in standalone mode — the user is browsing, not
    /// committing to a review session.
    func start(database: DatabaseService, bookId: String?) {
        self.database = database
        self.bookId = bookId
        self.unitMode = false
        self.activeUnit = nil

        let savedChapter = UserDefaults.standard.integer(forKey: progressKey)
        self.chapterIndex = savedChapter
        self.pronunciation.voice = accent == .us ? PronunciationService.Voice.us : PronunciationService.Voice.uk

        loadChapter()
    }

    /// Unit-driven entry: consume a pre-resolved StudyUnit from
    /// Today/UnitPreview. The chapter browser is bypassed; the unit's
    /// words become THE chapter for this session. Word completions emit
    /// derived FSRS ratings (see advance()).
    func start(unit: StudyUnit, database: DatabaseService) {
        self.database = database
        self.bookId = nil
        self.unitMode = true
        self.activeUnit = unit
        self.pronunciation.voice = accent == .us ? PronunciationService.Voice.us : PronunciationService.Voice.uk

        // Install the unit's words as the "chapter".
        self.chapterIndex = 0
        self.totalChapters = 1
        self.words = unit.cards.compactMap { unit.words[$0.wordId] }
        if wordOrder == .shuffle { self.words.shuffle() }

        guard !self.words.isEmpty else { phase = .empty; return }

        currentIndex = 0
        wordsCompleted = 0
        totalMistakes = 0
        totalInputs = 0
        totalCorrect = 0
        accumulatedTime = 0
        activeStartTime = nil
        wordResults = []
        showWordCard = false
        setupCurrentWord()
        phase = .idle
    }

    /// Called when any key is pressed while idle → enter typing mode
    func activate() {
        guard phase == .idle else { return }
        phase = .typing
        activeStartTime = Date()
        wordStartTime = Date()
        if let word = currentWord {
            pronunciation.speak(word.spelling)
            startLoopIfNeeded()
        }
    }

    /// Called on Esc or window blur → pause to idle
    func deactivate() {
        guard phase == .typing else { return }
        // Accumulate time spent in this active session
        if let start = activeStartTime {
            accumulatedTime += Date().timeIntervalSince(start)
        }
        activeStartTime = nil
        phase = .idle
        stopLoop()
    }

    func handleKeystroke(_ char: Character) {
        guard phase == .typing, !isWordComplete else { return }
        let target = targetSpelling.lowercased()
        let targetChars = Array(target)

        guard cursorPosition < targetChars.count else { return }

        if showWordCard { showWordCard = false }

        totalInputs += 1

        if char == targetChars[cursorPosition] {
            // Correct
            letterStates[cursorPosition] = .correct
            cursorPosition += 1
            totalCorrect += 1
            playCorrect()

            if cursorPosition >= targetChars.count {
                wordComplete()
            }
        } else {
            // Wrong
            letterStates[cursorPosition] = .wrong
            wordMistakes += 1
            totalMistakes += 1
            playWrong()

            switch errorMode {
            case .retryChar:
                let pos = cursorPosition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, pos < self.letterStates.count else { return }
                    if self.letterStates[pos] == .wrong {
                        self.letterStates[pos] = .untyped
                    }
                }
            case .resetWord:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self else { return }
                    self.letterStates = Array(repeating: .untyped, count: self.targetSpelling.count)
                    self.cursorPosition = 0
                }
            }
        }
    }

    func skipWord() {
        advanceToNext()
    }

    func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        wordsCompleted = max(0, wordsCompleted - 1)
        setupCurrentWord()
        if phase == .typing { startLoopIfNeeded() }
    }

    func goToWord(at index: Int) {
        guard index >= 0, index < words.count else { return }
        currentIndex = index
        setupCurrentWord()
        if phase == .typing { startLoopIfNeeded() }
    }

    func nextChapter() {
        chapterIndex += 1
        saveProgress()
        loadChapter()
    }

    func previousChapter() {
        guard chapterIndex > 0 else { return }
        chapterIndex -= 1
        saveProgress()
        loadChapter()
    }

    func repeatChapter() {
        loadChapter()
    }

    func startDictationChapter() {
        hideMode = .all
        loadChapter()
    }

    func cycleHideMode() {
        let modes = HideMode.allCases
        let idx = modes.firstIndex(of: hideMode) ?? 0
        hideMode = modes[(idx + 1) % modes.count]
    }

    func toggleWordCard() {
        showWordCard.toggle()
    }

    func replayPronunciation() {
        guard let word = currentWord else { return }
        pronunciation.speak(word.spelling)
    }

    func toggleLoopPronunciation() {
        loopPronunciation.toggle()
        if loopPronunciation && phase == .typing {
            startLoopIfNeeded()
        } else {
            stopLoop()
        }
    }

    // MARK: - Private

    private func saveProgress() {
        UserDefaults.standard.set(chapterIndex, forKey: progressKey)
    }

    private func loadChapter() {
        guard let db = database, let bookId else {
            phase = .empty
            return
        }

        do {
            let totalWords = try db.fetchWordCount(inBook: bookId)
            totalChapters = (totalWords + chapterSize - 1) / chapterSize

            if chapterIndex >= totalChapters { chapterIndex = max(0, totalChapters - 1) }

            let offset = chapterIndex * chapterSize
            words = try db.fetchWordsPage(inBook: bookId, offset: offset, limit: chapterSize)

            // Shuffle if needed
            if wordOrder == .shuffle {
                words.shuffle()
            }

            if words.isEmpty {
                phase = .empty
            } else {
                currentIndex = 0
                wordsCompleted = 0
                totalMistakes = 0
                totalInputs = 0
                totalCorrect = 0
                accumulatedTime = 0
                activeStartTime = nil
                wordResults = []
                showWordCard = false
                setupCurrentWord()
                phase = .idle
                saveProgress()
            }
        } catch {
            print("Failed to load chapter: \(error)")
            phase = .empty
        }
    }

    private func setupCurrentWord() {
        let spelling = targetSpelling
        letterStates = Array(repeating: .untyped, count: spelling.count)
        cursorPosition = 0
        isWordComplete = false
        wordMistakes = 0
        showWordCard = false
        wordStartTime = phase == .typing ? Date() : nil
        // Generate random visibility for .random hide mode (40% chance hidden)
        randomLetterVisible = spelling.map { _ in Double.random(in: 0...1) > 0.4 }
    }

    /// Check if a letter at given index should be hidden based on current hide mode
    func shouldHideLetter(at index: Int, char: Character) -> Bool {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        switch hideMode {
        case .none: return false
        case .vowels: return vowels.contains(Character(char.lowercased()))
        case .consonants: return char.isLetter && !vowels.contains(Character(char.lowercased()))
        case .random: return index < randomLetterVisible.count && !randomLetterVisible[index]
        case .all: return true
        }
    }

    private func wordComplete() {
        isWordComplete = true
        wordsCompleted += 1
        playComplete()
        stopLoop()

        let duration = wordStartTime.map { Date().timeIntervalSince($0) } ?? 0
        if let word = currentWord {
            wordResults.append((word: word, mistakes: wordMistakes, duration: duration))
        }

        recordTypingLog(mistakes: wordMistakes, duration: duration)
        applyDerivedFSRSRatingIfApplicable(mistakes: wordMistakes)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.advanceToNext()
        }
    }

    /// Cross-pollinate Typing → FSRS in unit mode. The rules:
    ///
    /// - Only fires in `unitMode` (i.e. user came from Today → UnitPreview).
    ///   Standalone Typing (free chapter browsing) doesn't touch reviewCard.
    /// - Only applies when the card is `state != .new` AND already due
    ///   (`dueDate <= now`). This is the key safety gate: we don't let
    ///   Typing skip the New→Learning bootstrap (otherwise users could
    ///   "type their way past" all initial flashcard exposure), and we
    ///   don't pull future reviews forward (FSRS already decided the card
    ///   isn't due — overriding would distort the schedule).
    /// - mistakes → rating mapping mirrors human intuition:
    ///     0 mistakes  → Good (smooth recall)
    ///     1–2         → Hard (knew it but stumbled)
    ///     3+          → Again (didn't really know it)
    /// - Persists via FSRSEngine.schedule + db.updateCard +
    ///   db.insertReviewLog so the same card seen in Flashcard tomorrow
    ///   reflects today's typing as if it had been a flashcard rating.
    private func applyDerivedFSRSRatingIfApplicable(mistakes: Int) {
        guard unitMode, let db = database, let word = currentWord else { return }
        // Recap units are practice mode — never write back to FSRS even
        // though they qualify as "unit mode". The user is re-practicing
        // today's words, not committing to a new review.
        if activeUnit?.kind.skipsFSRSWriteback == true { return }
        guard let card = try? db.fetchReviewCard(forWord: word.id) else { return }
        // Safety gate: only mature-enough + due cards may receive a
        // typing-derived rating. New cards must be bootstrapped via
        // Flashcard's reveal cycle.
        guard card.state != .new, card.dueDate <= Date() else { return }

        let rating: Rating = switch mistakes {
        case 0: .good
        case 1, 2: .hard
        default: .again
        }

        let result = engine.schedule(card: card)
        let updated: ReviewCard = switch rating {
        case .again: result.again
        case .hard: result.hard
        case .good: result.good
        case .easy: result.easy   // unreachable here; mapping never picks easy
        }

        do {
            try db.updateCard(updated)
            try db.insertReviewLog(ReviewLog(
                cardId: card.id,
                rating: rating,
                state: card.state,
                elapsedDays: card.elapsedDays,
                scheduledDays: updated.scheduledDays
            ))
        } catch {
            print("Typing derived FSRS update failed: \(error)")
        }
    }

    private func advanceToNext() {
        if currentIndex + 1 < words.count {
            currentIndex += 1
            setupCurrentWord()
            if phase == .typing {
                wordStartTime = Date()
                if let word = currentWord {
                    pronunciation.speak(word.spelling)
                    startLoopIfNeeded()
                }
            }
        } else {
            phase = .chapterComplete
        }
    }

    private func startLoopIfNeeded() {
        stopLoop()
        guard loopPronunciation, let word = currentWord else { return }
        loopTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .typing, !self.isWordComplete else {
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

    private func recordTypingLog(mistakes: Int, duration: TimeInterval?) {
        guard let db = database, let word = currentWord else { return }
        do {
            try db.insertTypingLog(
                wordId: word.id,
                bookId: bookId,
                mistakes: mistakes,
                duration: duration,
                mode: hideMode == .none ? "typing" : "dictation_\(hideMode.rawValue)"
            )
        } catch {
            print("Failed to record typing log: \(error)")
        }
    }
}
