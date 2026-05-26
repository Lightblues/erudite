import Foundation
import AppKit
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

    enum ErrorMode: String {
        case retryChar  // retry current character (default)
        case resetWord  // reset entire word from beginning
    }

    // MARK: - Published State

    var phase: Phase = .loading
    var displayMode: DisplayMode = .typing
    var errorMode: ErrorMode = .retryChar
    var showWordCard: Bool = false  // space to show full card

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

    // MARK: - Progress persistence key
    private var progressKey: String {
        "typing_chapter_\(bookId ?? "all")"
    }

    // MARK: - Public API

    func start(database: DatabaseService, bookId: String?) {
        self.database = database
        self.bookId = bookId

        // Restore progress
        let savedChapter = UserDefaults.standard.integer(forKey: progressKey)
        self.chapterIndex = savedChapter

        loadChapter()
    }

    func handleKeystroke(_ char: Character) {
        guard phase == .typing, !isWordComplete else { return }
        let target = targetSpelling.lowercased()
        let targetChars = Array(target)

        guard cursorPosition < targetChars.count else { return }

        // Dismiss card view on typing
        if showWordCard { showWordCard = false }

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

            // Play system error sound
            NSSound.beep()

            switch errorMode {
            case .retryChar:
                // Reset current char after brief delay
                let pos = cursorPosition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, pos < self.letterStates.count else { return }
                    if self.letterStates[pos] == .wrong {
                        self.letterStates[pos] = .untyped
                    }
                }
            case .resetWord:
                // Reset entire word after brief delay
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
    }

    func goToWord(at index: Int) {
        guard index >= 0, index < words.count else { return }
        currentIndex = index
        setupCurrentWord()
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

    func goToChapter(_ chapter: Int) {
        chapterIndex = chapter
        saveProgress()
        loadChapter()
    }

    func toggleDictation() {
        displayMode = displayMode == .typing ? .dictation : .typing
    }

    func toggleWordCard() {
        showWordCard.toggle()
    }

    func replayPronunciation() {
        guard let word = currentWord else { return }
        pronunciation.speak(word.spelling)
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

            // Clamp chapter index
            if chapterIndex >= totalChapters { chapterIndex = max(0, totalChapters - 1) }

            let offset = chapterIndex * chapterSize
            words = try db.fetchWordsPage(inBook: bookId, offset: offset, limit: chapterSize)

            if words.isEmpty {
                phase = .empty
            } else {
                currentIndex = 0
                wordsCompleted = 0
                totalMistakes = 0
                showWordCard = false
                setupCurrentWord()
                phase = .typing
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

        // Auto-play pronunciation
        if !spelling.isEmpty {
            pronunciation.speak(spelling)
        }
    }

    private func wordComplete() {
        isWordComplete = true
        wordsCompleted += 1

        // TODO: Record typing stats to DB (word, mistakes, time)

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
