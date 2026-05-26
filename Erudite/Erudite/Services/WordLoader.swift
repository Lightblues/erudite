import Foundation

// MARK: - Word Loader
// Loads word data from bundled JSON and imports into database.

struct WordLoader {

    struct WordDatabase: Codable {
        let version: String
        let generatedAt: String
        let wordCount: Int
        let words: [Word]

        enum CodingKeys: String, CodingKey {
            case version
            case generatedAt = "generated_at"
            case wordCount = "word_count"
            case words
        }
    }

    /// Load words from the bundled words.json resource
    static func loadBundledWords() throws -> [Word] {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json", subdirectory: "Data") else {
            throw WordLoaderError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let db = try decoder.decode(WordDatabase.self, from: data)
        return db.words
    }

    /// Seed the database with bundled words if empty
    static func seedDatabaseIfNeeded(database: DatabaseService) async throws {
        let existingWords = try database.fetchAllWords()
        guard existingWords.isEmpty else { return }

        let words = try loadBundledWords()
        try database.insertWords(words)
        try database.createCardsForNewWords(words)
    }
}

enum WordLoaderError: Error, LocalizedError {
    case fileNotFound
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Bundled words.json not found in app resources"
        case .decodingFailed(let error):
            return "Failed to decode words.json: \(error.localizedDescription)"
        }
    }
}
