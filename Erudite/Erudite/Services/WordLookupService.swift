import Foundation
import AppKit
import Observation

// MARK: - Word Lookup Service

/// Provides word lookup with local DB, API fallback, and permanent caching.
@Observable
final class WordLookupService {
    private var cache: [String: Word?] = [:]
    private let database: DatabaseService
    private let api = DictionaryAPIService()

    init(database: DatabaseService) {
        self.database = database
    }

    // MARK: - Sync lookup (local DB only, instant)

    /// Look up a word in local DB (instant). Returns nil if not found locally.
    func lookup(_ spelling: String) -> Word? {
        let key = spelling.lowercased()
        if let cached = cache[key] {
            return cached
        }
        let word = try? database.fetchWord(bySpelling: spelling)
        if word != nil {
            cache[key] = word
        }
        return word
    }

    // MARK: - Async lookup (local DB → API → cache)

    /// Look up a word: first local DB, then API if not found.
    /// Results are permanently cached to the database.
    func lookupAsync(_ spelling: String) async -> LookupResult {
        let key = spelling.lowercased()

        // Check local DB first
        if let cached = cache[key], let word = cached {
            return .found(word)
        }
        if let word = try? database.fetchWord(bySpelling: spelling) {
            cache[key] = word
            return .found(word)
        }

        // Query API
        guard let word = await api.lookup(key) else {
            cache[key] = nil  // Mark as "not found" to avoid repeated API calls
            return .notFound(spelling)
        }

        // Cache to DB permanently
        do {
            try database.insertCachedWord(word)
        } catch {
            print("[WordLookup] Failed to cache word: \(error)")
        }
        cache[key] = word
        return .found(word)
    }

    // MARK: - Eudic fallback

    /// Open the word in Eudic dictionary app via URL scheme.
    static func openInEudic(_ spelling: String) {
        let encoded = spelling.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spelling
        if let url = URL(string: "eudic://dict/\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Instance method for convenience
    func openInEudic(_ spelling: String) {
        Self.openInEudic(spelling)
    }
}

// MARK: - Lookup Result

enum LookupResult {
    case found(Word)
    case notFound(String)
}
