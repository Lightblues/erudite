import Foundation

// MARK: - Dictionary API Service

/// Multi-source dictionary lookup with priority:
/// 1. Merriam-Webster Collegiate + Thesaurus (if keys configured)
/// 2. Free Dictionary API (fallback, no key required)
///
/// Results include a source tag for cache upgrade logic.
final class DictionaryAPIService: Sendable {

    // MARK: - Public API

    /// Look up a word from the best available API source.
    /// Returns a Word struct if found, nil if all sources fail.
    func lookup(_ spelling: String) async -> Word? {
        let config = AppConfig.shared

        // Priority 1: Merriam-Webster (richer data: etymology, examples, thesaurus)
        if config.hasMWKeys {
            if let word = await lookupMW(spelling, config: config) {
                return word
            }
        }

        // Priority 2: Free Dictionary API (fallback)
        return await lookupFreeDictionary(spelling)
    }

    /// Check if a cached word should be upgraded (was from lower-priority source)
    func shouldUpgrade(_ word: Word) -> Bool {
        // Upgrade if it was cached from Free Dictionary and MW keys are now available
        return word.tags.contains("source:free_dict") && AppConfig.shared.hasMWKeys
    }

    // MARK: - Merriam-Webster

    private func lookupMW(_ spelling: String, config: AppConfig) async -> Word? {
        let encoded = spelling.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spelling

        // Fetch collegiate (definitions, examples, etymology)
        let collegiateURL = URL(string: "https://dictionaryapi.com/api/v3/references/collegiate/json/\(encoded)?key=\(config.mwDictionaryKey)")!
        // Fetch thesaurus (synonyms, antonyms)
        let thesaurusURL = URL(string: "https://dictionaryapi.com/api/v3/references/thesaurus/json/\(encoded)?key=\(config.mwThesaurusKey)")!

        do {
            async let collegiateData = fetchJSON(from: collegiateURL)
            async let thesaurusData = fetchJSON(from: thesaurusURL)

            let (colData, thesData) = await (try collegiateData, try? thesaurusData)

            // Parse collegiate response
            guard let entries = try? JSONSerialization.jsonObject(with: colData) as? [[String: Any]],
                  let entry = entries.first,
                  entry["meta"] != nil else {
                // API returns string array (suggestions) when word not found
                return nil
            }

            return parseMWResponse(entry: entry, thesaurus: thesData, spelling: spelling)
        } catch {
            print("[DictionaryAPI] MW lookup failed for '\(spelling)': \(error.localizedDescription)")
            return nil
        }
    }

    private func parseMWResponse(entry: [String: Any], thesaurus: Data?, spelling: String) -> Word {
        // Definitions + examples
        var definitions: [Definition] = []
        var examples: [Example] = []
        let fl = entry["fl"] as? String ?? ""  // functional label (part of speech)

        if let defArray = entry["def"] as? [[String: Any]] {
            for def in defArray {
                if let sseq = def["sseq"] as? [[[Any]]] {
                    for senseGroup in sseq {
                        for item in senseGroup {
                            guard let arr = item as? [Any],
                                  arr.count >= 2,
                                  arr[0] as? String == "sense",
                                  let sense = arr[1] as? [String: Any],
                                  let dt = sense["dt"] as? [[Any]] else { continue }

                            var defText = ""
                            for dtItem in dt {
                                if let type = dtItem.first as? String {
                                    if type == "text", let text = dtItem.last as? String {
                                        defText = cleanMWMarkup(text)
                                    }
                                    if type == "vis", let visList = dtItem.last as? [[String: Any]] {
                                        for vis in visList {
                                            if let t = vis["t"] as? String {
                                                examples.append(Example(
                                                    sentence: cleanMWMarkup(t),
                                                    source: "Merriam-Webster"
                                                ))
                                            }
                                        }
                                    }
                                }
                            }
                            if !defText.isEmpty {
                                definitions.append(Definition(
                                    partOfSpeech: fl,
                                    english: defText,
                                    chinese: ""
                                ))
                            }
                        }
                    }
                }
            }
        }

        // Etymology
        var etymology: String? = nil
        if let et = entry["et"] as? [[Any]] {
            for item in et {
                if let type = item.first as? String, type == "text",
                   let text = item.last as? String {
                    etymology = cleanMWMarkup(text)
                }
            }
        }

        // Phonetic
        var phonetic: String? = nil
        if let hwi = entry["hwi"] as? [String: Any],
           let prs = hwi["prs"] as? [[String: Any]],
           let first = prs.first,
           let mw = first["mw"] as? String {
            phonetic = "/\(mw)/"
        }

        // Synonyms & Antonyms from Thesaurus
        var synonymGroups: [[String]] = []
        var antonyms: [String] = []
        if let thesData = thesaurus,
           let thesEntries = try? JSONSerialization.jsonObject(with: thesData) as? [[String: Any]],
           let thesEntry = thesEntries.first,
           let meta = thesEntry["meta"] as? [String: Any] {
            if let syns = meta["syns"] as? [[String]] {
                synonymGroups = syns.map { Array($0.prefix(8)) }
            }
            if let ants = meta["ants"] as? [[String]] {
                antonyms = Array(ants.flatMap { $0 }.prefix(8))
            }
        }

        // Build mnemonic from etymology if available
        var mnemonics: [String] = []
        if let etym = etymology {
            mnemonics = [etym]
        }

        return Word(
            id: spelling.lowercased(),
            spelling: spelling.lowercased(),
            phonetic: phonetic,
            definitions: definitions,
            roots: nil,
            synonymGroups: synonymGroups,
            antonyms: antonyms,
            sentiment: .neutral,
            frequency: .common,
            examples: Array(examples.prefix(3)),
            mnemonics: mnemonics,
            tags: ["source:mw"]
        )
    }

    // MARK: - Free Dictionary API (fallback)

    private func lookupFreeDictionary(_ spelling: String) async -> Word? {
        let encoded = spelling.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spelling
        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            let entries = try JSONDecoder().decode([FreeDictEntry].self, from: data)
            guard let entry = entries.first else { return nil }

            return mapFreeDictToWord(entry, spelling: spelling)
        } catch {
            print("[DictionaryAPI] Free Dictionary lookup failed for '\(spelling)': \(error.localizedDescription)")
            return nil
        }
    }

    private func mapFreeDictToWord(_ entry: FreeDictEntry, spelling: String) -> Word {
        var definitions: [Definition] = []
        var allSynonyms: Set<String> = []
        var allAntonyms: Set<String> = []

        for meaning in entry.meanings {
            for syn in meaning.synonyms { allSynonyms.insert(syn) }
            for ant in meaning.antonyms { allAntonyms.insert(ant) }
            for def in meaning.definitions {
                definitions.append(Definition(
                    partOfSpeech: meaning.partOfSpeech,
                    english: def.definition,
                    chinese: ""
                ))
                for syn in def.synonyms { allSynonyms.insert(syn) }
                for ant in def.antonyms { allAntonyms.insert(ant) }
            }
        }

        let phonetic = entry.phonetic ?? entry.phonetics.first(where: { $0.text != nil })?.text

        return Word(
            id: spelling.lowercased(),
            spelling: spelling.lowercased(),
            phonetic: phonetic,
            definitions: definitions,
            roots: nil,
            synonymGroups: allSynonyms.isEmpty ? [] : [Array(allSynonyms.prefix(10))],
            antonyms: Array(allAntonyms.prefix(6)),
            sentiment: .neutral,
            frequency: .common,
            examples: [],
            mnemonics: [],
            tags: ["source:free_dict"]
        )
    }

    // MARK: - Helpers

    private func fetchJSON(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Clean MW markup: {bc} = bold colon, {it}...{/it} = italic, {wi}...{/wi} = word italic
    private func cleanMWMarkup(_ text: String) -> String {
        text.replacingOccurrences(of: "{bc}", with: "")
            .replacingOccurrences(of: "{it}", with: "")
            .replacingOccurrences(of: "{/it}", with: "")
            .replacingOccurrences(of: "{wi}", with: "")
            .replacingOccurrences(of: "{/wi}", with: "")
            .replacingOccurrences(of: "{ldquo}", with: "\u{201C}")
            .replacingOccurrences(of: "{rdquo}", with: "\u{201D}")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Free Dictionary Response Models

private struct FreeDictEntry: Codable {
    let word: String
    let phonetic: String?
    let phonetics: [FreeDictPhonetic]
    let meanings: [FreeDictMeaning]
}

private struct FreeDictPhonetic: Codable {
    let text: String?
    let audio: String?
}

private struct FreeDictMeaning: Codable {
    let partOfSpeech: String
    let definitions: [FreeDictDefinition]
    let synonyms: [String]
    let antonyms: [String]
}

private struct FreeDictDefinition: Codable {
    let definition: String
    let synonyms: [String]
    let antonyms: [String]
    let example: String?
}
