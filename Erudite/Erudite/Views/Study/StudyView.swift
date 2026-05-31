import SwiftUI

// MARK: - Study View (FSRS Card Session)

struct StudyView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = StudyViewModel()
    @State private var showWordList = false

    /// Units shown when the user opens this tab without a pinned unit.
    /// Loaded once on appear; we don't re-fetch on every re-render.
    @State private var pickerUnits: [StudyUnit] = []
    @State private var pickerLoaded: Bool = false

    /// True iff we should show the unit picker instead of the flashcard
    /// content. We sit on the picker until the user explicitly picks
    /// a unit OR a unit is pinned via Today→UnitPreview.
    @State private var showingPicker: Bool = false

    var body: some View {
        ZStack {
            if showingPicker {
                pickerLanding
            } else {
                flashcardContent
                // Keyboard capture is only active during a real session.
                KeyCaptureView(
                    onKeyDown: { event in handleKeyEvent(event) },
                    isActive: appState.selectedTab == .flashcard && !showWordList && appState.focusZone == .main
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if let db = appState.databaseService {
                if let unit = appState.currentUnit {
                    // Unit-driven entry from Today → UnitPreview → Flashcard.
                    showingPicker = false
                    viewModel.start(unit: unit, database: db)
                    appState.currentUnit = nil
                } else {
                    // No pinned unit → show the picker instead of running
                    // the legacy mixed-queue path.
                    showingPicker = true
                    await loadPickerUnits()
                }
            }
        }
        .onChange(of: appState.currentUnit?.id) { _, newId in
            // If a new unit gets pinned while we're on this tab (e.g. user
            // hopped to Today, picked a different unit, came back), consume it.
            if let unit = appState.currentUnit, newId != nil, let db = appState.databaseService {
                showingPicker = false
                viewModel.start(unit: unit, database: db)
                appState.currentUnit = nil
            }
        }
    }

    // MARK: - Picker Landing
    //
    // What the user sees when they click the Flashcard tab without first
    // picking a unit on Today. Same UnitPickerView component as Today,
    // so the experience is identical regardless of entry point.

    @ViewBuilder
    private var pickerLanding: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Pick a unit to study")
                    .font(.title2.weight(.bold))
                    .padding(.top, 24)

                Text("These are the same units shown on Today. Pick one to start a Flashcard session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if pickerLoaded {
                    UnitPickerView(
                        units: pickerUnits,
                        onPick: { unit in
                            // Start the unit directly in this tab — no
                            // sheet preview here, since the user has
                            // already committed to Flashcard.
                            if let db = appState.databaseService {
                                showingPicker = false
                                viewModel.start(unit: unit, database: db)
                            }
                        },
                        header: nil,
                        emptyTitle: "All caught up!",
                        emptyMessage: "No reviews due. Switch to Today to see your overall plan."
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

    private var flashcardContent: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView("Loading cards...")
            case .idle:
                idleContent
            case .empty:
                emptyState
            case .studying:
                studyContent
            case .unitComplete:
                unitCompleteState
            case .complete:
                completeState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Key Handling (via KeyCaptureView — always has focus)

    private func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // Escape: deactivate (pause) from studying. From .unitComplete, Esc
        // ends the session (the user's "I'm done" exit).
        if event.isEscape {
            if viewModel.phase == .studying {
                viewModel.deactivate()
            } else if viewModel.phase == .unitComplete {
                viewModel.endSession()
            }
            return true
        }

        // Unit complete: Space/Return to continue, Q to stop.
        if viewModel.phase == .unitComplete {
            if event.isSpace || event.isReturn {
                viewModel.continueAfterUnit()
                return true
            }
            if event.char == "q" {
                viewModel.endSession()
                return true
            }
            return true
        }

        // In idle: any key resumes
        if viewModel.phase == .idle {
            if event.isSpace || event.isReturn {
                viewModel.activate()
                return true
            }
            if event.isRightArrow || event.char == "n" {
                viewModel.activate()
                viewModel.skip()
                return true
            }
            if event.isLeftArrow || event.char == "p" {
                viewModel.activate()
                viewModel.goBack()
                return true
            }
            if event.char == "q" {
                viewModel.endSession()
                return true
            }
            // Any letter: just activate
            if let c = event.char, c.isLetter {
                viewModel.activate()
                return true
            }
            return true  // consume all
        }

        // Only handle remaining keys during active study
        guard viewModel.phase == .studying else { return true }

        // Space: toggle reveal
        if event.isSpace {
            viewModel.toggleReveal()
            return true
        }

        // Rating: 1234 number keys + jkl;
        if let c = event.char {
            switch c {
            case "1", "j":
                if viewModel.isRevealed { viewModel.rate(.again) }
                return true
            case "2", "k":
                if viewModel.isRevealed { viewModel.rate(.hard) }
                return true
            case "3", "l":
                if viewModel.isRevealed { viewModel.rate(.good) }
                return true
            case "4", ";":
                viewModel.rate(.easy)
                return true
            case "r":
                viewModel.replayPronunciation()
                return true
            case "q":
                viewModel.endSession()
                return true
            case "n":
                viewModel.skip()
                return true
            case "p":
                viewModel.goBack()
                return true
            default:
                break
            }
        }

        // Arrow keys
        if event.isRightArrow { viewModel.skip(); return true }
        if event.isLeftArrow { viewModel.goBack(); return true }

        return true  // consume all keys to prevent system beep
    }

    // MARK: - Idle Content (Paused)

    private var idleContent: some View {
        VStack(spacing: 0) {
            headerBar.padding(.horizontal).padding(.vertical, 12)
            Divider()

            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Paused")
                    .font(.title2)
                    .fontWeight(.medium)
                Text("Press Space to continue")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.cardsStudied) done · \(viewModel.cardsRemaining + 1) remaining")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            Divider()
            footerBar.padding(.horizontal).padding(.vertical, 8)
        }
    }

    // MARK: - Study Content

    private var studyContent: some View {
        VStack(spacing: 0) {
            headerBar.padding(.horizontal).padding(.vertical, 12)
            Divider()

            Spacer()

            // Card
            if let word = viewModel.currentWord {
                cardView(word: word)
            }

            // Prev / Next navigation preview
            navigationPreview
                .padding(.top, 12)

            Spacer()

            // Rating buttons (shown after reveal)
            if viewModel.isRevealed {
                ratingButtons
            } else {
                revealHint
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            // Progress
            Label("\(viewModel.cardsStudied) done", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

            if let card = viewModel.currentCard {
                Text(card.state.label)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cardStateColor(card.state).opacity(0.15), in: Capsule())
                    .foregroundStyle(cardStateColor(card.state))
            }

            Label("\(viewModel.cardsRemaining) left", systemImage: "rectangle.stack")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

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

            // Loop pronunciation
            Toggle(isOn: Binding(
                get: { viewModel.loopPronunciation },
                set: { _ in viewModel.toggleLoopPronunciation() }
            )) {
                Text("Loop").font(.caption)
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Spacer()

            HStack(spacing: 12) {
                shortcutHint("Space", label: "Toggle")
                shortcutHint("←→", label: "Nav")
                shortcutHint("1-4", label: "Rate")
                shortcutHint("Esc", label: "Pause")
                shortcutHint("Q", label: "Quit")
            }

            Spacer()

            Button { viewModel.replayPronunciation() } label: {
                Label("Replay", systemImage: "speaker.wave.2").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Word List Popover

    private var wordListPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review Queue")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollViewReader { proxy in
                List {
                    // Current word
                    if let word = viewModel.currentWord, let card = viewModel.currentCard {
                        HStack {
                            Text("▶").font(.caption)
                            Text(word.spelling).font(.body.monospaced()).fontWeight(.bold)
                            Spacer()
                            if let def = word.definitions.first {
                                Text(def.chinese).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(card.state.label).font(.caption2)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(cardStateColor(card.state).opacity(0.15), in: Capsule())
                                .foregroundStyle(cardStateColor(card.state))
                        }
                        .listRowBackground(Color.accentColor.opacity(0.1))
                        .id("current")
                    }

                    // Queue
                    ForEach(Array(viewModel.queueWords.enumerated()), id: \.element.word.id) { index, item in
                        Button {
                            viewModel.goToWord(at: index)
                            showWordList = false
                        } label: {
                            HStack {
                                Text("\(index + 1)").font(.caption).foregroundStyle(.tertiary)
                                    .frame(width: 20, alignment: .trailing)
                                Text(item.word.spelling).font(.body.monospaced())
                                Spacer()
                                if let def = item.word.definitions.first {
                                    Text(def.chinese).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Text(item.card.state.label).font(.caption2)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(cardStateColor(item.card.state).opacity(0.15), in: Capsule())
                                    .foregroundStyle(cardStateColor(item.card.state))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .frame(width: 360, height: 400)
                .onAppear {
                    proxy.scrollTo("current", anchor: .top)
                }
            }
        }
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
                Button { viewModel.skip() } label: {
                    HStack(spacing: 4) {
                        Text(next.spelling).font(.caption)
                        Image(systemName: "chevron.right").font(.caption2)
                    }.foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            } else { Spacer().frame(width: 80) }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Card View

    private func cardView(word: Word) -> some View {
        VStack(spacing: 20) {
            // Front: always visible
            VStack(spacing: 8) {
                Text(word.spelling)
                    .font(.system(size: 36, weight: .bold, design: .serif))

                if let phonetic = word.phonetic {
                    Text(phonetic)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Replay pronunciation button
                HStack(spacing: 8) {
                    Button {
                        viewModel.replayPronunciation()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("Replay pronunciation (R)")
                }
            }

            if viewModel.isRevealed {
                Divider()
                    .padding(.horizontal, 40)

                // Back: definitions (scrollable to prevent overflow)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(word.definitions.enumerated()), id: \.offset) { _, def in
                            HStack(alignment: .top, spacing: 8) {
                                if !def.partOfSpeech.isEmpty {
                                    Text(def.partOfSpeech)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.orange)
                                        .frame(width: 32, alignment: .trailing)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(def.chinese)
                                        .font(.body)
                                    if !def.english.isEmpty {
                                        InteractiveText(text: def.english, font: .callout, color: .secondary)
                                    }
                                }
                            }
                        }

                        // Example sentence
                        if let example = word.examples.first {
                            InteractiveText(text: example.sentence, font: .callout, color: .secondary, italic: true)
                                .padding(.top, 4)
                        }

                        // Mnemonic
                        if let mnemonic = word.mnemonics.first {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                InteractiveText(text: mnemonic, font: .callout, color: .primary.opacity(0.8))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Synonyms
                        if !word.synonymGroups.isEmpty {
                            let synonyms = Array(word.synonymGroups.flatMap { $0 }.prefix(6))
                            SynonymChipsView(synonyms: synonyms)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(32)
        .frame(maxWidth: 500)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .onTapGesture {
            viewModel.toggleReveal()
        }
    }

    // MARK: - Reveal Hint

    private var revealHint: some View {
        VStack(spacing: 6) {
            Text("Press Space to reveal")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                shortcutHint("Space", label: "Reveal")
                shortcutHint("4 ;", label: "Easy→skip")
                shortcutHint("→ n", label: "Skip")
                shortcutHint("R", label: "Replay")
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: - Rating Buttons

    private var ratingButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ratingButton(.again, keys: "1 j", color: .red)
                ratingButton(.hard, keys: "2 k", color: .orange)
                ratingButton(.good, keys: "3 l", color: .green)
                ratingButton(.easy, keys: "4 ;", color: .blue)
            }

            // Shortcut legend
            HStack(spacing: 16) {
                shortcutHint("Space", label: "Toggle")
                shortcutHint("← p", label: "Back")
                shortcutHint("→ n", label: "Skip")
                shortcutHint("R", label: "Replay")
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 24)
    }

    private func ratingButton(_ rating: Rating, keys: String, color: Color) -> some View {
        Button {
            viewModel.rate(rating)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: rating.icon)
                    .font(.title3)
                Text(rating.label)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(viewModel.intervalLabel(for: rating))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(keys)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 80, height: 72)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private func shortcutHint(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All caught up!")
                .font(.title2)
                .fontWeight(.bold)

            Text("No cards due for review.\nNew cards will be available tomorrow.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Unit Complete State (between units)
    //
    // Mid-session checkpoint shown every `unitSize` ratings in legacy
    // (non-unit-mode) sessions. Uses the shared SessionSummaryView so
    // the layout matches the end-of-session summary; only the heading
    // and actions differ.

    private var unitCompleteState: some View {
        SessionSummaryView(
            result: viewModel.unitResult(),
            heading: "Unit \(viewModel.unitsCompleted) complete · \(viewModel.cardsRemaining) left",
            primaryAction: .init("Continue", systemImage: "arrow.right.circle.fill") {
                viewModel.continueAfterUnit()
            },
            secondaryAction: .init("Stop", systemImage: "stop.circle", role: .cancel) {
                viewModel.endSession()
            }
        )
    }

    // MARK: - Complete State (whole session done)

    private var completeState: some View {
        SessionSummaryView(
            result: viewModel.sessionResult(),
            heading: viewModel.inUnitMode ? "Unit complete" : "Session complete",
            primaryAction: viewModel.inUnitMode
                ? .init("Back to Today", systemImage: "house") {
                    appState.selectedTab = .today
                }
                : .init("Study More", systemImage: "arrow.right.circle.fill") {
                    if let db = appState.databaseService {
                        viewModel.start(database: db)
                    }
                }
        )
    }

    // MARK: - Helpers

    private func cardStateColor(_ state: CardState) -> Color {
        switch state {
        case .new: .blue
        case .learning: .orange
        case .review: .green
        case .relearning: .red
        }
    }

    private func ratingColor(_ rating: Rating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }
}
