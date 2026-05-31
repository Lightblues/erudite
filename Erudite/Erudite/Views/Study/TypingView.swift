import SwiftUI

// MARK: - Typing Practice View (qwerty-learner style)

struct TypingView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = TypingViewModel()
    @State private var showWordList = false

    /// Units shown when the user opens this tab without a pinned unit.
    /// Same shape as Flashcard's empty-state picker so the entry
    /// experience is consistent.
    @State private var pickerUnits: [StudyUnit] = []
    @State private var pickerLoaded: Bool = false
    @State private var showingPicker: Bool = false

    var body: some View {
        ZStack {
            if showingPicker {
                pickerLanding
            } else {
                VStack(spacing: 0) {
                    switch viewModel.phase {
                    case .loading:
                        ProgressView("Loading chapter...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .idle:
                        idleContent
                    case .typing:
                        typingContent
                    case .chapterComplete:
                        chapterCompleteView
                    case .empty:
                        ContentUnavailableView(
                            "No Words Available",
                            systemImage: "character.book.closed",
                            description: Text("Select a unit on Today to start a typing session.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Keyboard capture layer
                KeyCaptureView(
                    onKeyDown: { event in handleKeyEvent(event) },
                    isActive: appState.selectedTab == .typing && !showWordList && appState.focusZone == .main
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            viewModel.deactivate()
        }
        .task {
            if let db = appState.databaseService {
                if let unit = appState.currentUnit {
                    // Unit-driven entry from Today → UnitPreview → Typing.
                    showingPicker = false
                    viewModel.start(unit: unit, database: db)
                    appState.currentUnit = nil
                } else {
                    // No pinned unit → show the picker. Old behavior was
                    // to load the persisted chapter index here; that lives
                    // in Library's Chapter view now.
                    showingPicker = true
                    await loadPickerUnits()
                }
            }
        }
        .onChange(of: appState.currentUnit?.id) { _, newId in
            if let unit = appState.currentUnit, newId != nil, let db = appState.databaseService {
                showingPicker = false
                viewModel.start(unit: unit, database: db)
                appState.currentUnit = nil
            }
        }
    }

    // MARK: - Picker Landing

    @ViewBuilder
    private var pickerLanding: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Pick a unit to type")
                    .font(.title2.weight(.bold))
                    .padding(.top, 24)

                Text("Same units shown on Today. Type-mode emits FSRS feedback for already-due cards (0 mistakes → Good, 1–2 → Hard, 3+ → Again).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)

                if pickerLoaded {
                    UnitPickerView(
                        units: pickerUnits,
                        onPick: { unit in
                            if let db = appState.databaseService {
                                showingPicker = false
                                viewModel.start(unit: unit, database: db)
                            }
                        },
                        header: nil,
                        emptyTitle: "All caught up!",
                        emptyMessage: "No reviews due. Library has chapter-by-chapter typing if you want to drill spelling."
                    )
                    .frame(maxWidth: 560)
                } else {
                    ProgressView().padding(.top, 32)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func loadPickerUnits() async {
        guard let db = appState.databaseService else { return }
        let builder = StudyQueueBuilder(db: db)
        self.pickerUnits = (try? builder.buildTodayUnits(
            bookId: appState.activeBookId,
            unitSize: appState.settings.unitSize
        )) ?? []
        self.pickerLoaded = true
    }

    // MARK: - Idle Content

    private var idleContent: some View {
        VStack(spacing: 0) {
            headerBar.padding(.horizontal).padding(.vertical, 12)
            Divider()

            Spacer()
            VStack(spacing: 16) {
                if let word = viewModel.currentWord {
                    wordInfoSection(word: word)
                }
                Text("Press any key to start")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                Text("Ch \(viewModel.chapterIndex + 1) · \(viewModel.words.count) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            Divider()
            footerBar.padding(.horizontal).padding(.vertical, 8)
        }
    }

    // MARK: - Typing Content

    private var typingContent: some View {
        VStack(spacing: 0) {
            headerBar.padding(.horizontal).padding(.vertical, 12)
            Divider()

            Spacer()

            if viewModel.showWordCard, let word = viewModel.currentWord {
                wordCardView(word: word)
            } else {
                VStack(spacing: 24) {
                    if let word = viewModel.currentWord {
                        wordInfoSection(word: word)
                    }
                    letterSlotsView
                    navigationPreview
                }
                .frame(maxWidth: 600)
            }

            Spacer()
            Divider()

            // Stats bar
            statsBar.padding(.horizontal).padding(.vertical, 6)
            Divider()
            footerBar.padding(.horizontal).padding(.vertical, 8)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 8) {
            // Top row: chapter info + exit
            HStack {
                Text("Ch \(viewModel.chapterIndex + 1)/\(viewModel.totalChapters)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(viewModel.chapterProgress)
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Button { appState.selectedTab = .today } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            // Settings row
            HStack(spacing: 16) {
                // Accent
                HStack(spacing: 4) {
                    Text("Accent").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { viewModel.accent },
                        set: { viewModel.accent = $0 }
                    )) {
                        ForEach(TypingViewModel.Accent.allCases, id: \.self) { a in
                            Text(a.label).tag(a)
                        }
                    }
                    .fixedSize()
                }

                // Display mode
                HStack(spacing: 4) {
                    Text("Display").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { viewModel.hideMode },
                        set: { viewModel.hideMode = $0 }
                    )) {
                        ForEach(TypingViewModel.HideMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .fixedSize()
                }

                // Error mode
                HStack(spacing: 4) {
                    Text("Error").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { viewModel.errorMode },
                        set: { viewModel.errorMode = $0 }
                    )) {
                        ForEach(TypingViewModel.ErrorMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .fixedSize()
                }

                // Word order
                HStack(spacing: 4) {
                    Text("Order").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { viewModel.wordOrder },
                        set: { viewModel.wordOrder = $0 }
                    )) {
                        ForEach(TypingViewModel.WordOrder.allCases, id: \.self) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .fixedSize()
                }

                // Loop pronunciation
                Toggle(isOn: Binding(
                    get: { viewModel.loopPronunciation },
                    set: { _ in viewModel.toggleLoopPronunciation() }
                )) {
                    Text("Loop Audio").font(.caption)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Stats Bar (live)

    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem("Time", value: formatTime(viewModel.elapsedTime))
            statItem("WPM", value: String(format: "%.1f", viewModel.wpm))
            statItem("Inputs", value: "\(viewModel.totalInputs)")
            statItem("Correct", value: "\(viewModel.totalCorrect)")
            statItem("Accuracy", value: viewModel.totalInputs > 0 ? "\(Int(viewModel.accuracy * 100))%" : "—")
            statItem("Mistakes", value: "\(viewModel.totalMistakes)")
        }
        .font(.caption)
    }

    private func statItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).fontWeight(.medium).monospacedDigit()
            Text(label).foregroundStyle(.tertiary)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Word Info

    private func wordInfoSection(word: Word) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(word.definitions.prefix(2).enumerated()), id: \.offset) { _, def in
                HStack(spacing: 6) {
                    if !def.partOfSpeech.isEmpty {
                        Text(def.partOfSpeech)
                            .font(.callout).foregroundStyle(.blue).fontWeight(.medium)
                    }
                    Text(def.chinese).font(.title3)
                }
            }
            if let phonetic = word.phonetic {
                Text(phonetic).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Full Word Card

    private func wordCardView(word: Word) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            WordPopoverView(word: word, onDismiss: {
                viewModel.toggleWordCard()
            })
        }
        .frame(maxWidth: 500, maxHeight: 400)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Letter Slots

    private var letterSlotsView: some View {
        let letters = Array(viewModel.targetSpelling)
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
        let hidden = viewModel.shouldHideLetter(at: index, char: letter)

        let displayChar: String = {
            switch state {
            case .correct: return String(letter)
            case .wrong: return String(letter)
            case .untyped: return hidden ? "_" : String(letter)
            }
        }()

        let color: Color = {
            switch state {
            case .correct: return .green
            case .wrong: return .red
            case .untyped: return hidden ? .secondary : .primary.opacity(0.4)
            }
        }()

        return Text(displayChar)
            .font(.system(size: 32, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 36, height: 48)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isCursor ? Color.accentColor.opacity(0.1) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isCursor ? Color.accentColor : Color.clear, lineWidth: 2))
    }

    // MARK: - Navigation Preview

    private var navigationPreview: some View {
        HStack {
            if let prev = viewModel.previousWord {
                Button { viewModel.goBack() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.caption2)
                        Text(prev.spelling).font(.caption)
                    }.foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            } else { Spacer().frame(width: 80) }

            Spacer()

            Button { showWordList.toggle() } label: {
                Label("Word List", systemImage: "list.bullet").font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .popover(isPresented: $showWordList) { wordListPopover }

            Spacer()

            if let next = viewModel.nextWord {
                Button { viewModel.skipWord() } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.hideMode == .all ? "•••" : next.spelling).font(.caption)
                        Image(systemName: "chevron.right").font(.caption2)
                    }.foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            } else { Spacer().frame(width: 80) }
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
                            Text("\(index + 1)").font(.caption).foregroundStyle(.tertiary)
                                .frame(width: 24, alignment: .trailing)
                            Text(word.spelling).font(.body.monospaced())
                                .fontWeight(index == viewModel.currentIndex ? .bold : .regular)
                            Spacer()
                            if let def = word.definitions.first {
                                Text(def.chinese).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if index < viewModel.wordsCompleted {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                            } else if index == viewModel.currentIndex {
                                Image(systemName: "pencil.circle.fill").foregroundStyle(.blue).font(.caption)
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
                if let current = viewModel.currentWord { proxy.scrollTo(current.id, anchor: .center) }
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Button { viewModel.previousChapter() } label: {
                Label("Prev Ch", systemImage: "chevron.left")
            }.buttonStyle(.borderless).disabled(viewModel.chapterIndex == 0)

            Spacer()

            HStack(spacing: 12) {
                shortcutHint("⌘R", "Replay")
                shortcutHint("Space", "Card")
                shortcutHint("←→", "Nav")
                shortcutHint("Esc", "Pause")
            }

            Spacer()

            Button { viewModel.nextChapter() } label: {
                Label("Next Ch", systemImage: "chevron.right")
            }.buttonStyle(.borderless).disabled(viewModel.chapterIndex >= viewModel.totalChapters - 1)
        }
    }

    private func shortcutHint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 3) {
            Text(key).font(.caption2.monospaced())
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(action).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Chapter Complete

    private var chapterCompleteView: some View {
        // Use the shared SessionSummaryView so the layout matches
        // Flashcard's session-complete state. Mode-specific WPM is
        // populated automatically when SessionResult.wpm is non-nil.
        SessionSummaryView(
            result: viewModel.sessionResult(),
            heading: viewModel.unitMode ? "Unit complete" : "Chapter complete",
            primaryAction: primaryActionForChapterComplete,
            secondaryAction: secondaryActionForChapterComplete
        )
    }

    private var primaryActionForChapterComplete: SessionSummaryView.Action {
        if viewModel.unitMode {
            // Unit mode: go back to Today and pick another unit.
            return .init("Back to Today", systemImage: "house") {
                appState.selectedTab = .today
            }
        }
        // Standalone (legacy): if there's a next chapter, that's the
        // primary; otherwise repeat current.
        if viewModel.chapterIndex < viewModel.totalChapters - 1 {
            return .init("Next Chapter", systemImage: "arrow.right.circle.fill") {
                viewModel.nextChapter()
            }
        }
        return .init("Repeat Chapter", systemImage: "arrow.clockwise") {
            viewModel.repeatChapter()
        }
    }

    private var secondaryActionForChapterComplete: SessionSummaryView.Action? {
        if viewModel.unitMode { return nil }
        return .init("Dictation", systemImage: "ear", role: .cancel) {
            viewModel.startDictationChapter()
        }
    }

    // MARK: - Key Handling (via KeyCaptureView)

    private func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // Escape: deactivate (pause)
        if event.isEscape {
            if viewModel.phase == .typing {
                viewModel.deactivate()
            }
            return true
        }

        // In idle: any key (letter or space) activates — but does NOT input to word
        if viewModel.phase == .idle {
            if event.isSpace {
                viewModel.activate()
                return true
            }
            if let c = event.char, c.isLetter {
                viewModel.activate()
                return true
            }
            if event.isTab { viewModel.cycleHideMode(); return true }
            if event.isRightArrow { viewModel.skipWord(); return true }
            if event.isLeftArrow { viewModel.goBack(); return true }
            return true  // consume all
        }

        guard viewModel.phase == .typing else { return true }

        // Space: toggle word card
        if event.isSpace {
            viewModel.toggleWordCard()
            return true
        }

        // Cmd+R: replay
        if event.char == "r" && event.hasCommand {
            viewModel.replayPronunciation()
            return true
        }

        // Tab: cycle hide mode
        if event.isTab {
            viewModel.cycleHideMode()
            return true
        }

        // Arrows
        if event.isLeftArrow { viewModel.goBack(); return true }
        if event.isRightArrow { viewModel.skipWord(); return true }

        // Return: advance if complete
        if event.isReturn {
            if viewModel.isWordComplete { viewModel.skipWord() }
            return true
        }

        // Letter input
        if !viewModel.showWordCard {
            let chars = event.characters.lowercased()
            if chars.count == 1, let char = chars.first, char.isLetter {
                viewModel.handleKeystroke(char)
                return true
            }
            if event.characters == "-" {
                viewModel.handleKeystroke(Character("-"))
                return true
            }
        }

        return true  // consume all
    }
}
