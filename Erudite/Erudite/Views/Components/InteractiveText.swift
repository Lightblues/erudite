import SwiftUI

// MARK: - Interactive Text

/// A text view that makes English words clickable for dictionary lookup.
/// Clicking a word shows a popover with its definition (if in local DB)
/// or opens Eudic dictionary as fallback.
struct InteractiveText: View {
    let text: String
    var font: Font = .callout
    var color: Color = .secondary
    var italic: Bool = false

    @Environment(AppState.self) private var appState
    @State private var popoverWord: Word?

    var body: some View {
        let tokens = Self.tokenize(text)
        TextFlowLayout(spacing: 0) {
            ForEach(tokens) { token in
                if token.isWord && !Self.isCommonWord(token.text) {
                    Text(token.text)
                        .font(font)
                        .italic(italic)
                        .foregroundStyle(.primary.opacity(0.9))
                        .underline(true, color: color.opacity(0.25))
                        .onTapGesture { handleTap(token: token) }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                } else {
                    Text(token.text)
                        .font(font)
                        .italic(italic)
                        .foregroundStyle(color)
                }
            }
        }
        .popover(item: $popoverWord, arrowEdge: .bottom) { word in
            WordPopoverView(word: word) {
                popoverWord = nil
            }
        }
    }

    private func handleTap(token: TextToken) {
        guard token.isWord else { return }
        guard let service = appState.wordLookupService else { return }

        let cleaned = token.text.lowercased()
        if let word = service.lookup(cleaned) {
            popoverWord = word
        } else {
            service.openInEudic(cleaned)
        }
    }

    // MARK: - Common Words Filter

    /// Words too common to look up — basic function words, pronouns, prepositions, etc.
    private static let commonWords: Set<String> = [
        // Articles & determiners
        "a", "an", "the", "this", "that", "these", "those",
        // Pronouns
        "i", "me", "my", "mine", "we", "us", "our", "ours",
        "you", "your", "yours", "he", "him", "his", "she", "her", "hers",
        "it", "its", "they", "them", "their", "theirs", "who", "whom", "whose",
        "what", "which", "one", "ones", "self",
        // Prepositions
        "in", "on", "at", "to", "for", "of", "with", "by", "from",
        "up", "out", "off", "into", "onto", "upon", "about", "over",
        "under", "below", "above", "between", "among", "through", "during",
        "before", "after", "since", "until", "than",
        // Conjunctions
        "and", "or", "but", "nor", "so", "yet", "if", "then", "else",
        "when", "while", "as", "because", "although", "though",
        // Common verbs (most basic forms)
        "is", "am", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "having", "do", "does", "did", "doing",
        "will", "would", "shall", "should", "may", "might", "can", "could",
        "get", "got", "go", "goes", "went", "gone", "come", "came",
        "make", "made", "take", "took", "give", "gave", "let",
        "say", "said", "tell", "told", "see", "saw", "know", "knew",
        // Common adjectives / adverbs
        "not", "no", "yes", "very", "too", "also", "just", "only",
        "more", "most", "less", "least", "much", "many", "few",
        "all", "some", "any", "every", "each", "both", "other", "another",
        "such", "same", "own", "new", "old", "big", "small", "good", "bad",
        "well", "how", "here", "there", "where", "now", "still",
        // Common nouns & misc
        "thing", "things", "way", "time", "people", "man", "woman",
        "day", "year", "part", "place", "case", "group", "fact",
    ]

    /// Returns true if the word is too common/simple to warrant a dictionary lookup.
    static func isCommonWord(_ word: String) -> Bool {
        let lower = word.lowercased()
        // Single characters are never interesting
        if lower.count <= 2 { return true }
        return commonWords.contains(lower)
    }

    // MARK: - Tokenizer

    /// Splits text into word and non-word tokens, preserving order and whitespace.
    static func tokenize(_ text: String) -> [TextToken] {
        var tokens: [TextToken] = []
        var index = 0
        let chars = Array(text)
        let count = chars.count

        var currentStart = 0
        var inWord = false

        func flush(at end: Int) {
            guard currentStart < end else { return }
            let substring = String(chars[currentStart..<end])
            tokens.append(TextToken(id: index, text: substring, isWord: inWord))
            index += 1
        }

        for i in 0..<count {
            let c = chars[i]
            // Letters and apostrophes (for contractions like "don't")
            let charIsLetter = c.isLetter || c == Character("'") || c == Character("\u{2019}")
            if charIsLetter && !inWord {
                flush(at: i)
                currentStart = i
                inWord = true
            } else if !charIsLetter && inWord {
                flush(at: i)
                currentStart = i
                inWord = false
            }
        }
        flush(at: count)

        return tokens
    }
}

// MARK: - Text Token

struct TextToken: Identifiable {
    let id: Int
    let text: String
    let isWord: Bool
}

// MARK: - Text Flow Layout

/// A custom Layout that arranges views like text — wrapping to the next line when needed.
/// Unlike FlowLayout, this uses zero spacing between items to match natural text rendering.
struct TextFlowLayout: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: .init(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let pos = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                // Wrap to next line
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: min(maxX, maxWidth), height: y + rowHeight), positions)
    }
}
