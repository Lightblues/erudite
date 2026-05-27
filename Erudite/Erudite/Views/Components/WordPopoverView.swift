import SwiftUI

// MARK: - Word Popover View (Compact Dictionary Card)

/// A compact word card shown in a popover when a user clicks an interactive word.
/// Supports multi-layer lookup: English text inside the popover is also interactive.
struct WordPopoverView: View {
    let word: Word
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: spelling + phonetic
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.spelling)
                    .font(.system(size: 20, weight: .bold, design: .serif))

                if let phonetic = word.phonetic {
                    Text(phonetic)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Definitions (English part is interactive for multi-layer lookup)
            ForEach(Array(word.definitions.enumerated()), id: \.offset) { _, def in
                HStack(alignment: .top, spacing: 8) {
                    if !def.partOfSpeech.isEmpty {
                        Text(def.partOfSpeech)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 3))
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

            // First example (interactive)
            if let example = word.examples.first {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    InteractiveText(text: example.sentence, font: .callout, color: .secondary, italic: true)
                }
            }

            // Mnemonic (interactive)
            if let mnemonic = word.mnemonics.first {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption2)
                    InteractiveText(text: mnemonic, font: .caption, color: .primary.opacity(0.8))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Synonyms (each chip is tappable)
            if !word.synonymGroups.isEmpty {
                let synonyms = word.synonymGroups.flatMap { $0 }.prefix(5)
                SynonymChipsView(synonyms: Array(synonyms))
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}

// MARK: - Synonym Chips with Lookup

/// Individual synonym chips that are tappable for dictionary lookup.
struct SynonymChipsView: View {
    let synonyms: [String]
    var chipFont: Font = .caption
    var chipPaddingH: CGFloat = 6
    var chipPaddingV: CGFloat = 2

    @Environment(AppState.self) private var appState
    @State private var popoverWord: Word?
    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
                .font(.caption2)
                .foregroundStyle(.blue)
            ForEach(synonyms, id: \.self) { syn in
                Text(syn)
                    .font(chipFont)
                    .padding(.horizontal, chipPaddingH)
                    .padding(.vertical, chipPaddingV)
                    .background(.blue.opacity(0.1), in: Capsule())
                    .onTapGesture { handleTap(syn) }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            if let word = popoverWord {
                WordPopoverView(word: word) {
                    showPopover = false
                    popoverWord = nil
                }
            }
        }
    }

    private func handleTap(_ spelling: String) {
        guard let service = appState.wordLookupService else { return }
        let cleaned = spelling.lowercased()
        if let word = service.lookup(cleaned) {
            popoverWord = word
            showPopover = true
        } else {
            service.openInEudic(cleaned)
        }
    }
}
