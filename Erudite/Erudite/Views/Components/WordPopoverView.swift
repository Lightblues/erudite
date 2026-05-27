import SwiftUI

// MARK: - Word Popover View (Compact Dictionary Card)

/// A compact word card shown in a popover when a user clicks an interactive word.
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

            // Definitions
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
                            Text(def.english)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // First example
            if let example = word.examples.first {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(example.sentence)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            // Mnemonic
            if let mnemonic = word.mnemonics.first {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption2)
                    Text(mnemonic)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.8))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Synonyms (compact)
            if !word.synonymGroups.isEmpty {
                let synonyms = word.synonymGroups.flatMap { $0 }.prefix(5)
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    ForEach(Array(synonyms), id: \.self) { syn in
                        Text(syn)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}
