import Foundation
import AppKit
import Observation

// MARK: - Word Lookup Service

/// Provides word lookup with in-memory caching and Eudic fallback.
@Observable
final class WordLookupService {
    private var cache: [String: Word?] = [:]
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    /// Look up a word by its spelling (case-insensitive).
    /// Returns the Word if found in the local database, nil otherwise.
    func lookup(_ spelling: String) -> Word? {
        let key = spelling.lowercased()
        if let cached = cache[key] {
            return cached
        }
        let word = try? database.fetchWord(bySpelling: spelling)
        cache[key] = word
        return word
    }

    /// Open the word in Eudic dictionary app via URL scheme.
    func openInEudic(_ spelling: String) {
        let encoded = spelling.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spelling
        if let url = URL(string: "eudic://dict/\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Look up a word: if found locally, return it; otherwise open Eudic.
    /// Returns the Word if found locally, nil if fallback to Eudic.
    @discardableResult
    func lookupOrFallback(_ spelling: String) -> Word? {
        if let word = lookup(spelling) {
            return word
        }
        openInEudic(spelling)
        return nil
    }
}
