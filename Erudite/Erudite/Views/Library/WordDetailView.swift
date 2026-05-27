import SwiftUI

// MARK: - Word Detail View

struct WordDetailView: View {
    let word: Word

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                Divider()

                // Definitions
                definitionsSection

                // Examples
                if !word.examples.isEmpty {
                    examplesSection
                }

                // Mnemonics
                if !word.mnemonics.isEmpty {
                    mnemonicsSection
                }

                // Synonyms
                if !word.synonymGroups.isEmpty {
                    synonymsSection
                }

                // Word roots
                if let roots = word.roots {
                    rootsSection(roots)
                }

                // Metadata
                metadataSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(word.spelling)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(word.spelling)
                    .font(.system(size: 32, weight: .bold, design: .serif))

                if let phonetic = word.phonetic {
                    Text(phonetic)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                tierBadge(word.frequency)
            }
        }
    }

    // MARK: - Definitions

    private var definitionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Definitions", systemImage: "text.book.closed")
                .font(.headline)

            ForEach(Array(word.definitions.enumerated()), id: \.offset) { _, def in
                HStack(alignment: .top, spacing: 10) {
                    if !def.partOfSpeech.isEmpty {
                        Text(def.partOfSpeech)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(def.chinese)
                            .font(.body)
                        if !def.english.isEmpty {
                            InteractiveText(text: def.english, font: .callout, color: .secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Examples

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Examples", systemImage: "text.quote")
                .font(.headline)

            ForEach(Array(word.examples.enumerated()), id: \.offset) { _, example in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        InteractiveText(text: example.sentence, font: .callout, color: .secondary, italic: true)
                        Text(example.source)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Mnemonics

    private var mnemonicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mnemonics", systemImage: "lightbulb")
                .font(.headline)

            ForEach(word.mnemonics, id: \.self) { mnemonic in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    InteractiveText(text: mnemonic, font: .callout, color: .primary.opacity(0.85))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Synonyms

    private var synonymsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Synonyms", systemImage: "link")
                .font(.headline)

            ForEach(Array(word.synonymGroups.enumerated()), id: \.offset) { _, group in
                SynonymChipsView(synonyms: group, chipFont: .callout, chipPaddingH: 10, chipPaddingV: 4)
            }
        }
    }

    // MARK: - Roots

    private func rootsSection(_ roots: MorphemeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Word Roots", systemImage: "tree")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(Array(roots.segments.enumerated()), id: \.offset) { _, segment in
                    VStack(spacing: 2) {
                        Text(segment.text)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(segment.meaning)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(segment.type.rawValue)
                            .font(.caption2)
                            .foregroundStyle(morphemeColor(segment.type))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(morphemeColor(segment.type).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Text(roots.logic)
                .font(.callout)
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Info", systemImage: "info.circle")
                .font(.headline)

            HStack(spacing: 16) {
                metaItem("Frequency", value: word.frequency.label)
                metaItem("Sentiment", value: word.sentiment.rawValue)
                if !word.tags.isEmpty {
                    metaItem("Tags", value: word.tags.joined(separator: ", "))
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func tierBadge(_ tier: FrequencyTier) -> some View {
        Text(tier.label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
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

    private func morphemeColor(_ type: MorphemeType) -> Color {
        switch type {
        case .prefix: .purple
        case .root: .blue
        case .suffix: .green
        }
    }

    private func metaItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Flow Layout (simple horizontal wrap)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
