import Foundation
import Observation

// MARK: - Typing Practice ViewModel

@Observable
final class TypingViewModel {

    // MARK: - Types

    enum Phase {
        case loading
        case typing
        case chapterComplete
        case empty
    }

    enum LetterState {
        case untyped
        case correct
        case wrong
    }

    enum DisplayMode {
        case typing     // show all letters
        case dictation  // hide untyped letters
    }

    // MARK: - Published State

    var phase: Phase = .loading
    var displayMode: DisplayMode = .typing

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

    // Session stats
    var totalMistakes: Int = 0
    var wordsCompleted: Int = 0

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

    // MARK: - Dependencies

    private var database: DatabaseService?
    private var bookId: String?
    private let pronunciation = PronunciationService()

    // MARK: - Public API

    func start(database: DatabaseService, bookId: String?, chapter: Int = 0) {
        self.database = database
        self.bookId = bookId
        self.chapterIndex = chapter
        loadChapter()
    }

    func handleKeystroke(_ char: Character) {
        guard phase == .typing, !isWordComplete else { return }
        let target = targetSpelling.lowercased()
        let targetChars = Array(target)

        guard cursorPosition < targetChars.count else { return }

        if char == targetChars[cursorPosition] {
            // Correct
            letterStates[cursorPosition] = .correct
            cursorPosition += 1

            if cursorPosition >= targetChars.count {
                wordComplete()
            }
        } else {
            // Wrong
            letterStates[cursorPosition] = .wrong
            wordMistakes += 1
            totalMistakes += 1

            // Reset after brief delay
            let pos = cursorPosition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, pos < self.letterStates.count else { return }
                if self.letterStates[pos] == .wrong {
                    self.letterStates[pos] = .untyped
                }
            }
        }
    }

    func skipWord() {
        advanceToNext()
    }

    func nextChapter() {
        chapterIndex += 1
        loadChapter()
    }

    func previousChapter() {
        guard chapterIndex > 0 else { return }
        chapterIndex -= 1
        loadChapter()
    }

    func goToChapter(_ chapter: Int) {
        chapterIndex = chapter
        loadChapter()
    }

    func toggleDictation() {
        displayMode = displayMode == .typing ? .dictation : .typing
    }

    func replayPronunciation() {
        guard let word = currentWord else { return }
        pronunciation.speak(word.spelling)
    }

    // MARK: - Private

    private func loadChapter() {
        guard let db = database, let bookId else {
            phase = .empty
            return
        }

        do {
            let totalWords = try db.fetchWordCount(inBook: bookId)
            totalChapters = (totalWords + chapterSize - 1) / chapterSize
            let offset = chapterIndex * chapterSize
            words = try db.fetchWordsPage(inBook: bookId, offset: offset, limit: chapterSize)

            if words.isEmpty {
                phase = .empty
            } else {
                currentIndex = 0
                wordsCompleted = 0
                totalMistakes = 0
                setupCurrentWord()
                phase = .typing
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

        // Auto-play pronunciation
        if !spelling.isEmpty {
            pronunciation.speak(spelling)
        }
    }

    private func wordComplete() {
        isWordComplete = true
        wordsCompleted += 1

        // Auto-advance after brief pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.advanceToNext()
        }
    }

    private func advanceToNext() {
        if currentIndex + 1 < words.count {
            currentIndex += 1
            setupCurrentWord()
        } else {
            phase = .chapterComplete
        }
    }
}
