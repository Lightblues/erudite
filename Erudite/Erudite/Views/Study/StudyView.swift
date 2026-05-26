import SwiftUI

// MARK: - Study View (FSRS Card Session)

struct StudyView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = StudyViewModel()

    var body: some View {
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
        .task {
            if let db = appState.databaseService {
                viewModel.start(database: db, mode: appState.studyMode)
            }
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
                revealButton
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

                // Tier badge
                HStack(spacing: 8) {
                    tierBadge(word.frequency)
                    if let list = word.listIndex, let unit = word.unitIndex {
                        Text("List \(list) · Unit \(unit)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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
                                    Text(def.english)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Example sentence
                    if let example = word.examples.first {
                        Text(example.sentence)
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .lineLimit(3)
                    }

                    // Mnemonic
                    if let mnemonic = word.mnemonics.first {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text(mnemonic)
                                .font(.callout)
                                .foregroundStyle(.primary.opacity(0.8))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Synonyms
                    if !word.synonymGroups.isEmpty {
                        let synonyms = word.synonymGroups.flatMap { $0 }.prefix(6)
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            ForEach(Array(synonyms), id: \.self) { syn in
                                Text(syn)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.1), in: Capsule())
                            }
                        }
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

    // MARK: - Reveal Button

    private var revealButton: some View {
        Button {
            viewModel.reveal()
        } label: {
            Label("Show Answer", systemImage: "eye")
                .font(.title3)
                .frame(width: 200, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.space, modifiers: [])
        .padding(.bottom, 32)
    }

    // MARK: - Rating Buttons

    private var ratingButtons: some View {
        HStack(spacing: 12) {
            ForEach(Rating.allCases, id: \.self) { rating in
                Button {
                    viewModel.rate(rating)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: rating.icon)
                            .font(.title3)
                        Text(rating.label)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(viewModel.intervalLabel(for: rating))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 80, height: 64)
                }
                .buttonStyle(.bordered)
                .tint(ratingColor(rating))
            }
        }
        .padding(.bottom, 32)
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

    private func ratingColor(_ rating: Rating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
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
