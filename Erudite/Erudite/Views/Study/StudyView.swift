import SwiftUI

// MARK: - Study View (FSRS Card Session)

struct StudyView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = StudyViewModel()
    @FocusState private var isFocused: Bool

    var body: some View {
        flashcardContent
    }

    private var flashcardContent: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView("Loading cards...")
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
            // Auto-focus so keyboard shortcuts work immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onChange(of: appState.selectedTab) {
            // Re-focus when switching back to study tab
            if appState.selectedTab == .flashcard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
    }

    // MARK: - Key Handling

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Only handle keys during active study
        guard viewModel.phase == .studying else { return .ignored }

        switch press.key {
        // Space: reveal → then rate Good on second press
        case .space:
            if !viewModel.isRevealed {
                viewModel.reveal()
            } else {
                viewModel.rate(.good)
            }
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
        case KeyEquivalent("4"), KeyEquivalent(";"):
            if viewModel.isRevealed { viewModel.rate(.easy) }
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
        case KeyEquivalent("q"), .escape:
            viewModel.endSession()
            return .handled

        default:
            return .ignored
        }
    }

    // MARK: - Study Content

    private var studyContent: some View {
        VStack(spacing: 0) {
            // Progress bar
            progressHeader

            Spacer()

            // Card
            if let word = viewModel.currentWord {
                cardView(word: word)
            }

            Spacer()

            // Rating buttons (shown after reveal)
            if viewModel.isRevealed {
                ratingButtons
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                revealHint
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRevealed)
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

                // Back: definitions
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
                .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                shortcutHint("→ n", label: "Skip")
                shortcutHint("R", label: "Replay")
                shortcutHint("Q", label: "Quit")
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
                shortcutHint("Space", label: "Good")
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

    // MARK: - Progress Header

    private var progressHeader: some View {
        HStack {
            // Cards studied
            Label("\(viewModel.cardsStudied) done", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

            Spacer()

            // Card state
            if let card = viewModel.currentCard {
                Text(card.state.label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(cardStateColor(card.state).opacity(0.15), in: Capsule())
                    .foregroundStyle(cardStateColor(card.state))
            }

            Spacer()

            // Remaining
            Label("\(viewModel.cardsRemaining) left", systemImage: "rectangle.stack")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
