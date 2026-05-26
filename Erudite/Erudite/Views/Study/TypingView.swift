import SwiftUI

// MARK: - Typing Practice View (qwerty-learner style)

struct TypingView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = TypingViewModel()
    @State private var showWordList = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
            case .loading:
                ProgressView("Loading chapter...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .typing:
                typingContent

            case .chapterComplete:
                chapterCompleteView

            case .empty:
                ContentUnavailableView(
                    "No Words Available",
                    systemImage: "character.book.closed",
                    description: Text("Select a word book from the Today page first.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($isFocused)
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        .onAppear { isFocused = true }
        .onChange(of: appState.selectedTab) {
            if appState.selectedTab == .typing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
        .task {
            if let db = appState.databaseService {
                viewModel.start(database: db, bookId: appState.activeBookId)
            }
        }
    }

    // MARK: - Typing Content

    private var typingContent: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
                .padding(.horizontal)
                .padding(.vertical, 12)

            Divider()

            // Main typing area
            Spacer()

            if viewModel.showWordCard, let word = viewModel.currentWord {
                // Full word card (like flashcard mode)
                wordCardView(word: word)
            } else {
                VStack(spacing: 24) {
                    // Definition + phonetic
                    if let word = viewModel.currentWord {
                        wordInfoSection(word: word)
                    }

                    // Letter slots
                    letterSlotsView

                    // Prev/Next preview
                    navigationPreview
                }
                .frame(maxWidth: 600)
            }

            Spacer()

            Divider()

            // Footer
            footerBar
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            // Chapter info
            Text("Ch \(viewModel.chapterIndex + 1)/\(viewModel.totalChapters)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            // Progress
            Text(viewModel.chapterProgress)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            // Mistakes
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(viewModel.totalMistakes > 0 ? .red : .secondary)
                Text("\(viewModel.totalMistakes)")
                    .monospacedDigit()
            }
            .font(.subheadline)

            Spacer()

            // Mode toggles
            HStack(spacing: 8) {
                // Dictation toggle
                Button {
                    viewModel.toggleDictation()
                } label: {
                    Image(systemName: viewModel.displayMode == .typing ? "eye" : "eye.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Toggle dictation mode (Tab)")

                // Error mode toggle
                Button {
                    viewModel.errorMode = viewModel.errorMode == .retryChar ? .resetWord : .retryChar
                } label: {
                    Image(systemName: viewModel.errorMode == .retryChar ? "arrow.uturn.left.circle" : "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(viewModel.errorMode == .retryChar ? "Error: retry char" : "Error: reset word")
            }

            Spacer()

            // Exit
            Button {
                appState.selectedTab = .today
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Word Info

    private func wordInfoSection(word: Word) -> some View {
        VStack(spacing: 8) {
            // Definitions
            ForEach(Array(word.definitions.prefix(2).enumerated()), id: \.offset) { _, def in
                HStack(spacing: 6) {
                    if !def.partOfSpeech.isEmpty {
                        Text(def.partOfSpeech)
                            .font(.callout)
                            .foregroundStyle(.blue)
                            .fontWeight(.medium)
                    }
                    Text(def.chinese)
                        .font(.title3)
                }
            }

            // Phonetic
            if let phonetic = word.phonetic {
                Text(phonetic)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Full Word Card

    private func wordCardView(word: Word) -> some View {
        VStack(spacing: 16) {
            Text(word.spelling)
                .font(.system(size: 36, weight: .bold, design: .serif))

            if let phonetic = word.phonetic {
                Text(phonetic)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(maxWidth: 300)

            ForEach(Array(word.definitions.enumerated()), id: \.offset) { _, def in
                HStack(spacing: 8) {
                    if !def.partOfSpeech.isEmpty {
                        Text(def.partOfSpeech)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if !def.chinese.isEmpty {
                            Text(def.chinese)
                        }
                        if !def.english.isEmpty {
                            Text(def.english)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !word.synonymGroups.isEmpty {
                HStack {
                    Text("Syn:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(word.synonymGroups.flatMap { $0 }.prefix(5).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text("Press Space to dismiss")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: 500)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Letter Slots

    private var letterSlotsView: some View {
        let spelling = viewModel.targetSpelling
        let letters = Array(spelling)

        return HStack(spacing: 4) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                letterSlot(letter: letter, index: index)
            }
        }
        .padding(.vertical, 16)
    }

    private func letterSlot(letter: Character, index: Int) -> some View {
        let state = index < viewModel.letterStates.count ? viewModel.letterStates[index] : .untyped
        let isCursor = index == viewModel.cursorPosition && !viewModel.isWordComplete

        let displayChar: String = {
            switch state {
            case .correct:
                return String(letter)
            case .wrong:
                return String(letter)
            case .untyped:
                if viewModel.displayMode == .dictation {
                    return "_"
                }
                return String(letter)
            }
        }()

        let color: Color = {
            switch state {
            case .correct: return .green
            case .wrong: return .red
            case .untyped: return viewModel.displayMode == .dictation ? .secondary : .primary.opacity(0.4)
            }
        }()

        return Text(displayChar)
            .font(.system(size: 32, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 36, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCursor ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCursor ? Color.accentColor : Color.clear, lineWidth: 2)
            )
    }

    // MARK: - Navigation Preview

    private var navigationPreview: some View {
        HStack {
            // Previous word (clickable)
            if let prev = viewModel.previousWord {
                Button {
                    viewModel.goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption2)
                        Text(prev.spelling)
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 80)
            }

            Spacer()

            // Word list toggle
            Button {
                showWordList.toggle()
            } label: {
                Label("Word List", systemImage: "list.bullet")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showWordList) {
                wordListPopover
            }

            Spacer()

            // Next word (clickable)
            if let next = viewModel.nextWord {
                Button {
                    viewModel.skipWord()
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.displayMode == .dictation ? "•••" : next.spelling)
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 80)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Word List Popover

    private var wordListPopover: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(viewModel.words.enumerated()), id: \.element.id) { index, word in
                    Button {
                        viewModel.goToWord(at: index)
                        showWordList = false
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 24, alignment: .trailing)

                            Text(word.spelling)
                                .font(.body.monospaced())
                                .fontWeight(index == viewModel.currentIndex ? .bold : .regular)

                            Spacer()

                            if let def = word.definitions.first {
                                Text(def.chinese)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            if index < viewModel.wordsCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else if index == viewModel.currentIndex {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .id(word.id)
                    .listRowBackground(index == viewModel.currentIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                }
            }
            .listStyle(.plain)
            .frame(width: 360, height: 400)
            .onAppear {
                if let current = viewModel.currentWord {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            // Chapter navigation
            Button {
                viewModel.previousChapter()
            } label: {
                Label("Prev Ch", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.chapterIndex == 0)

            Spacer()

            // Shortcuts hint
            HStack(spacing: 12) {
                shortcutHint("Tab", "Dictation")
                shortcutHint("⌘R", "Replay")
                shortcutHint("Space", "Card")
                shortcutHint("←→", "Nav")
                shortcutHint("Esc", "Exit")
            }

            Spacer()

            Button {
                viewModel.nextChapter()
            } label: {
                Label("Next Ch", systemImage: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.chapterIndex >= viewModel.totalChapters - 1)
        }
    }

    private func shortcutHint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(action)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Chapter Complete

    private var chapterCompleteView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Chapter Complete!")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                Text("\(viewModel.words.count) words typed")
                    .font(.headline)
                Text("\(viewModel.totalMistakes) mistakes")
                    .font(.subheadline)
                    .foregroundStyle(viewModel.totalMistakes == 0 ? .green : .orange)
            }

            HStack(spacing: 16) {
                Button("Back to Today") {
                    appState.selectedTab = .today
                }
                .buttonStyle(.bordered)

                if viewModel.chapterIndex < viewModel.totalChapters - 1 {
                    Button("Next Chapter") {
                        viewModel.nextChapter()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Key Handling

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard viewModel.phase == .typing else { return .ignored }

        // Space: toggle word card view
        if press.key == .space {
            viewModel.toggleWordCard()
            return .handled
        }

        // Cmd+R: replay (avoids conflict with typing 'r')
        if press.key == KeyEquivalent("r") && press.modifiers.contains(.command) {
            viewModel.replayPronunciation()
            return .handled
        }

        // Tab: toggle dictation
        if press.key == .tab {
            viewModel.toggleDictation()
            return .handled
        }

        // Arrow keys: navigate words
        if press.key == .leftArrow {
            viewModel.goBack()
            return .handled
        }
        if press.key == .rightArrow {
            viewModel.skipWord()
            return .handled
        }

        // Escape: exit
        if press.key == .escape {
            appState.selectedTab = .today
            return .handled
        }

        // Return: advance if word complete
        if press.key == .return {
            if viewModel.isWordComplete {
                viewModel.skipWord()
            }
            return .handled
        }

        // Letter input (only when card not showing)
        if !viewModel.showWordCard {
            let chars = press.characters.lowercased()
            if chars.count == 1, let char = chars.first, char.isLetter {
                viewModel.handleKeystroke(char)
                return .handled
            }
            // Handle hyphen and space in words
            if press.characters == "-" || press.characters == " " {
                if let char = press.characters.first {
                    viewModel.handleKeystroke(char)
                    return .handled
                }
            }
        }

        return .ignored
    }
}
