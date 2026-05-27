import SwiftUI

// MARK: - Study View (FSRS Card Session)

struct StudyView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = StudyViewModel()
    @State private var showWordList = false
    @FocusState private var isFocused: Bool

    var body: some View {
        flashcardContent
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
            case .complete:
                completeState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress { press in
            handleKeyPress(press)
        }
        .task {
            if let db = appState.databaseService {
                viewModel.start(database: db, mode: appState.studyMode, bookId: appState.activeBookId)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onChange(of: appState.selectedTab) {
            if appState.selectedTab == .flashcard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
            }
        }
        .onChange(of: showWordList) {
            if !showWordList {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isFocused = true }
            }
        }
    }

    // MARK: - Key Handling

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Escape: deactivate (pause) from studying, go home from idle
        if press.key == .escape {
            if viewModel.phase == .studying {
                viewModel.deactivate()
                return .handled
            } else if viewModel.phase == .idle {
                appState.selectedTab = .today
                return .handled
            }
            return .ignored
        }

        // In idle: Space or rating keys resume
        if viewModel.phase == .idle {
            if press.key == .space {
                viewModel.activate()
                return .handled
            }
            // Allow navigation even in idle
            if press.key == .rightArrow || press.key == KeyEquivalent("n") {
                viewModel.activate()
                viewModel.skip()
                return .handled
            }
            if press.key == .leftArrow || press.key == KeyEquivalent("p") {
                viewModel.activate()
                viewModel.goBack()
                return .handled
            }
            return .ignored
        }

        // Only handle remaining keys during active study
        guard viewModel.phase == .studying else { return .ignored }

        switch press.key {
        // Space: toggle reveal
        case .space:
            viewModel.toggleReveal()
            return .handled

        // Rating: 1234 number keys + jkl;
        case KeyEquivalent("1"), KeyEquivalent("j"):
            if viewModel.isRevealed { viewModel.rate(.again) }
            return .handled
        case KeyEquivalent("2"), KeyEquivalent("k"):
            if viewModel.isRevealed { viewModel.rate(.hard) }
            return .handled
        case KeyEquivalent("3"), KeyEquivalent("l"):
            if viewModel.isRevealed { viewModel.rate(.good) }
            return .handled
        // Easy: allowed even without reveal (quick skip for known words)
        case KeyEquivalent("4"), KeyEquivalent(";"):
            viewModel.rate(.easy)
            return .handled

        // Navigation: skip / go back
        case .rightArrow, KeyEquivalent("n"):
            viewModel.skip()
            return .handled
        case .leftArrow, KeyEquivalent("p"):
            viewModel.goBack()
            return .handled

        // Replay pronunciation
        case KeyEquivalent("r"):
            viewModel.replayPronunciation()
            return .handled

        // End session
        case KeyEquivalent("q"):
            viewModel.endSession()
            return .handled

        default:
            return .ignored
        }
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
            Button { showWordList.toggle() } label: {
                Label("Word List", systemImage: "list.bullet").font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .popover(isPresented: $showWordList) { wordListPopover }

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

                // Tier badge + replay button
                HStack(spacing: 8) {
                    tierBadge(word.frequency)
                    Spacer().frame(width: 8)
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

    // MARK: - Complete State

    private var completeState: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Session Complete!")
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 32) {
                VStack {
                    Text("\(viewModel.cardsStudied)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text("Cards")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack {
                    Text(formatDuration(viewModel.sessionDuration))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.purple)
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Study More") {
                if let db = appState.databaseService {
                    viewModel.start(database: db)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top)
        }
    }

    // MARK: - Helpers

    private func tierBadge(_ tier: FrequencyTier) -> some View {
        Text(tier.label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tierColor(tier).opacity(0.15), in: Capsule())
            .foregroundStyle(tierColor(tier))
    }

    private func tierColor(_ tier: FrequencyTier) -> Color {
        switch tier {
        case .core: .red
        case .common: .blue
        case .advanced: .gray
        }
    }

    private func cardStateColor(_ state: CardState) -> Color {
        switch state {
        case .new: .blue
        case .learning: .orange
        case .review: .green
        case .relearning: .red
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }
}
