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
        case all        // hide all (full dictation)

        var label: String {
            switch self {
            case .none: "Show All"
            case .vowels: "Hide Vowels"
            case .consonants: "Hide Consonants"
            case .all: "Hide All"
            }
        }

        var icon: String {
            switch self {
            case .none: "eye"
            case .vowels: "eye.trianglebadge.exclamationmark"
            case .consonants: "eye.slash.circle"
            case .all: "eye.slash"
            }
        }

        func shouldHide(_ char: Character) -> Bool {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
            switch self {
            case .none: return false
            case .vowels: return vowels.contains(Character(char.lowercased()))
            case .consonants: return char.isLetter && !vowels.contains(Character(char.lowercased()))
            case .all: return true
            }
        }
    }

    enum ErrorMode: String, CaseIterable {
        case retryChar  // retry current character
        case resetWord  // reset entire word

        var label: String {
            switch self {
            case .retryChar: "Retry Char"
            case .resetWord: "Reset Word"
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

    // MARK: - Dependencies

    private var database: DatabaseService?
    private var bookId: String?
    private let pronunciation = PronunciationService()
    private var loopTimer: Timer?

    // Sound effects: use NSSound(named:) inline — sandbox-safe
    private func playCorrect() {
        NSSound(named: "Tink")?.play()
    }
    private func playWrong() {
        NSSound(named: "Basso")?.play()
    }
    private func playComplete() {
        NSSound(named: "Glass")?.play()
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
    }

    // MARK: - Public API

    func start(database: DatabaseService, bookId: String?) {
        self.database = database
        self.bookId = bookId

        let savedChapter = UserDefaults.standard.integer(forKey: progressKey)
        self.chapterIndex = savedChapter

        loadChapter()
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.advanceToNext()
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
