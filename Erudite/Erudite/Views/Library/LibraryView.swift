import SwiftUI

// MARK: - Library View (Word Lists + Browser)

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var words: [Word] = []
    @State private var selectedTier: FrequencyTier? = nil

    private var filteredWords: [Word] {
        var result = words
        if let tier = selectedTier {
            result = result.filter { $0.frequency == tier }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.spelling.lowercased().contains(query) ||
                $0.definitions.contains { d in
                    d.chinese.contains(query) || d.english.lowercased().contains(query)
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Word Library")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                // Tier filter
                Picker("Tier", selection: $selectedTier) {
                    Text("All (\(words.count))").tag(FrequencyTier?.none)
                    Text("Core (\(words.filter { $0.frequency == .core }.count))")
                        .tag(FrequencyTier?.some(.core))
                    Text("Common (\(words.filter { $0.frequency == .common }.count))")
                        .tag(FrequencyTier?.some(.common))
                    Text("Advanced (\(words.filter { $0.frequency == .advanced }.count))")
                        .tag(FrequencyTier?.some(.advanced))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
            }
            .padding()

            Divider()

            // Content
            if appState.isDBReady {
                if filteredWords.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    wordListView
                }
            } else {
                ProgressView("Loading database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $searchText, prompt: "Search words...")
        .task {
            await loadWords()
        }
    }

    private var wordListView: some View {
        List(filteredWords) { word in
            NavigationLink(value: word) {
                WordRow(word: word)
            }
        }
        .listStyle(.inset)
        .navigationDestination(for: Word.self) { word in
            WordDetailView(word: word)
        }
    }

    private func loadWords() async {
        guard let db = appState.databaseService else { return }
        do {
            words = try db.fetchAllWords()
        } catch {
            print("Failed to load words: \(error)")
        }
    }
}

// MARK: - Word Row

private struct WordRow: View {
    let word: Word

    var body: some View {
        HStack(spacing: 12) {
            // Frequency tier badge
            tierBadge

            // Word info
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.spelling)
                        .font(.headline)

                    if let phonetic = word.phonetic {
                        Text(phonetic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let def = word.definitions.first {
                    HStack(spacing: 4) {
                        if !def.partOfSpeech.isEmpty {
                            Text(def.partOfSpeech)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text(def.chinese)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Mnemonic indicator
            if !word.mnemonics.isEmpty {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            // Synonym count
            if !word.synonymGroups.isEmpty {
                let count = word.synonymGroups.flatMap { $0 }.count
                Text("\(count) syn")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }

            // List/Unit
            if let list = word.listIndex, let unit = word.unitIndex {
                Text("L\(list)U\(unit)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private var tierBadge: some View {
        let (color, label): (Color, String) = switch word.frequency {
        case .core: (.red, "C")
        case .common: (.blue, "M")
        case .advanced: (.gray, "A")
        }
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color, in: Circle())
    }
}
