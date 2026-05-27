import Foundation

// MARK: - Dictionary API Service

/// Fetches word definitions from the Free Dictionary API (dictionaryapi.dev).
/// Free, no API key required, data from Wiktionary (CC BY-SA 3.0).
final class DictionaryAPIService: Sendable {

    private let baseURL = "https://api.dictionaryapi.dev/api/v2/entries/en/"

    /// Look up a word from the Free Dictionary API.
    /// Returns a Word struct if found, nil if not found or network error.
    func lookup(_ spelling: String) async -> Word? {
        let encoded = spelling.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spelling
        guard let url = URL(string: "\(baseURL)\(encoded)") else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let entries = try JSONDecoder().decode([APIEntry].self, from: data)
            guard let entry = entries.first else { return nil }

            return mapToWord(entry, spelling: spelling)
        } catch {
            print("[DictionaryAPI] Failed to lookup '\(spelling)': \(error)")
            return nil
        }
    }

    // MARK: - Response Mapping

    private func mapToWord(_ entry: APIEntry, spelling: String) -> Word {
        // Definitions
        var definitions: [Definition] = []
        var allSynonyms: Set<String> = []
        var allAntonyms: Set<String> = []

        for meaning in entry.meanings {
            // Collect synonyms/antonyms at meaning level
            for syn in meaning.synonyms { allSynonyms.insert(syn) }
            for ant in meaning.antonyms { allAntonyms.insert(ant) }

            for def in meaning.definitions {
                definitions.append(Definition(
                    partOfSpeech: meaning.partOfSpeech,
                    english: def.definition,
                    chinese: ""  // API doesn't provide Chinese
                ))
                // Also collect definition-level synonyms/antonyms
                for syn in def.synonyms { allSynonyms.insert(syn) }
                for ant in def.antonyms { allAntonyms.insert(ant) }
            }
        }

        // Build synonym groups (single group with all synonyms)
        let synonymGroups: [[String]] = allSynonyms.isEmpty ? [] : [Array(allSynonyms.prefix(10))]

        // Phonetic (prefer the one with text)
        let phonetic = entry.phonetic ?? entry.phonetics.first(where: { $0.text != nil })?.text

        return Word(
            id: spelling.lowercased(),
            spelling: spelling.lowercased(),
            phonetic: phonetic,
            definitions: definitions,
            roots: nil,
            synonymGroups: synonymGroups,
            antonyms: Array(allAntonyms.prefix(6)),
            sentiment: .neutral,
            frequency: .common,
            examples: [],
            mnemonics: [],
            tags: ["api_cached"]
        )
    }
}

// MARK: - API Response Models

private struct APIEntry: Codable {
    let word: String
    let phonetic: String?
    let phonetics: [APIPhonetic]
    let meanings: [APIMeaning]
}

private struct APIPhonetic: Codable {
    let text: String?
    let audio: String?
}

private struct APIMeaning: Codable {
    let partOfSpeech: String
    let definitions: [APIDefinition]
    let synonyms: [String]
    let antonyms: [String]
}

private struct APIDefinition: Codable {
    let definition: String
    let synonyms: [String]
    let antonyms: [String]
    let example: String?
}
