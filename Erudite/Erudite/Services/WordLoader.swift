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

    /// Seed or upgrade the database with bundled words.
    ///
    /// Three paths:
    /// 1. **Fresh install** (no words yet) — insert everything, create
    ///    reviewCards, seed wordbooks.
    /// 2. **Upgrade** (DB version differs from bundled version) — UPDATE
    ///    existing word.data with new fields (e.g. v1.0 → v3.0 ai-enriched
    ///    mnemonics, examples, definitions). reviewCard / reviewLog /
    ///    user_content are NOT touched, so all FSRS progress and user-authored
    ///    mnemonics survive the upgrade. New words get fresh reviewCards.
    /// 3. **Up to date** (versions match) — fast path: no work.
    ///
    /// The bundled version is read from `words.json:version`. The DB stores
    /// the last-applied version under `meta(key='wordsVersion')`.
    static func seedDatabaseIfNeeded(database: DatabaseService) async throws {
        let bundle = try loadBundledDatabase()
        let bundledVersion = bundle.version
        let storedVersion = (try? database.metaValue(forKey: "wordsVersion")) ?? ""
        let existingWords = try database.fetchAllWords()

        if existingWords.isEmpty {
            // Fresh install
            try database.insertWords(bundle.words)
            try database.createCardsForNewWords(bundle.words)
            try seedWordBooks(database: database)
            try database.setMetaValue(bundledVersion, forKey: "wordsVersion")
            Log.app.info("Seeded \(bundle.words.count) words at version \(bundledVersion)")
        } else if storedVersion != bundledVersion {
            // Upgrade path: data version moved forward (or wasn't tracked yet).
            // UPDATE existing rows with new word.data; INSERT any new ones
            // and create reviewCards for them.
            let result = try database.upsertWordData(bundle.words)
            // Backfill cards only for the genuinely new words.
            if result.newInserted > 0 {
                let existingIds = Set(existingWords.map(\.id))
                let newWords = bundle.words.filter { !existingIds.contains($0.id) }
                try database.createCardsForNewWords(newWords)
            }
            // Books may also have changed shape — re-seed if missing.
            let books = try database.fetchWordBooks()
            if books.isEmpty {
                try seedWordBooks(database: database)
            }
            try database.setMetaValue(bundledVersion, forKey: "wordsVersion")
            Log.app.info(
                "Upgraded words.json: \(storedVersion.isEmpty ? "<unknown>" : storedVersion) → \(bundledVersion); "
                + "updated \(result.existingUpdated), inserted \(result.newInserted)"
            )
        } else {
            // Up to date — only ensure books are seeded (defensive).
            let books = try database.fetchWordBooks()
            if books.isEmpty {
                try seedWordBooks(database: database)
            }
        }
    }

    /// Load the full bundled database (so callers can use both `words` and `version`).
    static func loadBundledDatabase() throws -> WordDatabase {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json") else {
            throw WordLoaderError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(WordDatabase.self, from: data)
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
