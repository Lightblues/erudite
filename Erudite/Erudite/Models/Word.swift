import Foundation

// MARK: - Word (Core Entity)

nonisolated struct Word: Identifiable, Codable, Hashable {
    let id: String
    let spelling: String
    let phonetic: String?
    let definitions: [Definition]
    let roots: MorphemeBreakdown?
    let synonymGroups: [[String]]
    let antonyms: [String]
    let sentiment: Sentiment
    let frequency: FrequencyTier
    let examples: [Example]
    let mnemonics: [String]
    let tags: [String]

    init(
        id: String,
        spelling: String,
        phonetic: String? = nil,
        definitions: [Definition] = [],
        roots: MorphemeBreakdown? = nil,
        synonymGroups: [[String]] = [],
        antonyms: [String] = [],
        sentiment: Sentiment = .neutral,
        frequency: FrequencyTier = .common,
        examples: [Example] = [],
        mnemonics: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.spelling = spelling
        self.phonetic = phonetic
        self.definitions = definitions
        self.roots = roots
        self.synonymGroups = synonymGroups
        self.antonyms = antonyms
        self.sentiment = sentiment
        self.frequency = frequency
        self.examples = examples
        self.mnemonics = mnemonics
        self.tags = tags
    }
}

// MARK: - Definition

nonisolated struct Definition: Codable, Hashable {
    let partOfSpeech: String
    let english: String
    let chinese: String
}

// MARK: - Morpheme / Word Root

nonisolated struct MorphemeBreakdown: Codable, Hashable {
    let segments: [Morpheme]
    let logic: String
}

nonisolated struct Morpheme: Codable, Hashable {
    let text: String
    let type: MorphemeType
    let meaning: String
}

nonisolated enum MorphemeType: String, Codable, Hashable {
    case prefix
    case root
    case suffix
}

// MARK: - Example

nonisolated struct Example: Codable, Hashable {
    let sentence: String
    let source: String
}

// MARK: - Enums

nonisolated enum Sentiment: String, Codable, Hashable {
    case positive
    case negative
    case neutral
    case ambivalent
}

nonisolated enum FrequencyTier: Int, Codable, Hashable, Comparable {
    case core = 1
    case common = 2
    case advanced = 3

    static func < (lhs: FrequencyTier, rhs: FrequencyTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .core: "Core"
        case .common: "Common"
        case .advanced: "Advanced"
        }
    }
}
