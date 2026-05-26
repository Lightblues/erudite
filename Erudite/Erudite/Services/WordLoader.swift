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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            generatedAt = try container.decode(String.self, forKey: .generatedAt)
            wordCount = try container.decode(Int.self, forKey: .wordCount)
            words = try container.decode([Word].self, forKey: .words)
        }
    }

    struct WordBooksManifest: Codable {
        let version: String
        let books: [BookEntry]

        struct BookEntry: Codable {
            let id: String
            let name: String
            let exam: String
            let source: String
            let structure: String
            let wordCount: Int
            let words: [String]
        }
    }

    /// Load words from the bundled words.json resource
    static func loadBundledWords() throws -> [Word] {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json") else {
            throw WordLoaderError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let db = try decoder.decode(WordDatabase.self, from: data)
        return db.words
    }

    /// Load word books manifest
    static func loadBundledWordBooks() throws -> WordBooksManifest {
        guard let url = Bundle.main.url(forResource: "wordbooks", withExtension: "json") else {
            throw WordLoaderError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WordBooksManifest.self, from: data)
    }

    /// Seed the database with bundled words if empty
    static func seedDatabaseIfNeeded(database: DatabaseService) async throws {
        let existingWords = try database.fetchAllWords()

        if existingWords.isEmpty {
            // Fresh install: seed words + cards + books
            let words = try loadBundledWords()
            try database.insertWords(words)
            try database.createCardsForNewWords(words)
            try seedWordBooks(database: database)
        } else {
            // Existing install: ensure word books are seeded
            let books = try database.fetchWordBooks()
            if books.isEmpty {
                // Upgrade path: insert any new words, then seed books
                let allWords = try loadBundledWords()
                let existingIds = Set(existingWords.map(\.id))
                let newWords = allWords.filter { !existingIds.contains($0.id) }
                if !newWords.isEmpty {
                    try database.insertWords(newWords)
                    try database.createCardsForNewWords(newWords)
                }
                try seedWordBooks(database: database)
            }
        }
    }

    /// Seed word book metadata and entries
    static func seedWordBooks(database: DatabaseService) throws {
        let manifest = try loadBundledWordBooks()

        for bookEntry in manifest.books {
            let book = WordBook(
                id: bookEntry.id,
                name: bookEntry.name,
                exam: bookEntry.exam,
                source: bookEntry.source,
                wordCount: bookEntry.wordCount,
                structure: bookEntry.structure,
                isBuiltin: true
            )
            try database.insertWordBook(book)
            try database.insertWordBookEntries(bookId: book.id, wordIds: bookEntry.words)
        }
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
