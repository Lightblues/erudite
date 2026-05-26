import Foundation

// MARK: - Word (Core Entity)

struct Word: Identifiable, Codable, Hashable {
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

struct Definition: Codable, Hashable {
    let partOfSpeech: PartOfSpeech
    let english: String
    let chinese: String
}

enum PartOfSpeech: String, Codable, Hashable {
    case noun, verb, adj, adv, prep, conj
}

// MARK: - Morpheme / Word Root

struct MorphemeBreakdown: Codable, Hashable {
    let segments: [Morpheme]
    let logic: String
}

struct Morpheme: Codable, Hashable {
    let text: String
    let type: MorphemeType
    let meaning: String
}

enum MorphemeType: String, Codable, Hashable {
    case prefix
    case root
    case suffix
}

// MARK: - Example

struct Example: Codable, Hashable {
    let sentence: String
    let source: ExampleSource
}

enum ExampleSource: String, Codable, Hashable {
    case officialGuide
    case powerPrep
    case generated
    case custom
}

// MARK: - Enums

enum Sentiment: String, Codable, Hashable {
    case positive
    case negative
    case neutral
    case ambivalent
}

enum FrequencyTier: Int, Codable, Hashable, Comparable {
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
