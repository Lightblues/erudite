import Foundation
import Testing
@testable import Erudite

@Suite("Word Model Tests")
struct WordModelTests {

    @Test("Word decoding from JSON")
    func testWordDecoding() throws {
        let json = """
        {
            "id": "test",
            "spelling": "test",
            "phonetic": "/test/",
            "definitions": [{"partOfSpeech": "noun", "english": "a trial", "chinese": "测试"}],
            "roots": null,
            "synonymGroups": [["trial", "exam"]],
            "antonyms": [],
            "sentiment": "neutral",
            "frequency": 1,
            "examples": [],
            "mnemonics": [],
            "tags": []
        }
        """.data(using: .utf8)!

        let word = try JSONDecoder().decode(Word.self, from: json)
        #expect(word.id == "test")
        #expect(word.spelling == "test")
        #expect(word.frequency == .core)
        #expect(word.sentiment == .neutral)
        #expect(word.definitions.count == 1)
        #expect(word.synonymGroups.first?.contains("trial") == true)
    }

    @Test("Word round-trip encoding/decoding")
    func testWordRoundTrip() throws {
        let word = Word(
            id: "ephemeral",
            spelling: "ephemeral",
            phonetic: "/ɪˈfem.ər.əl/",
            definitions: [
                Definition(partOfSpeech: .adj, english: "lasting a short time", chinese: "短暂的")
            ],
            synonymGroups: [["transient", "fleeting"]],
            antonyms: ["permanent"],
            sentiment: .neutral,
            frequency: .core,
            mnemonics: ["一朝之花"]
        )

        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(Word.self, from: data)

        #expect(decoded.id == word.id)
        #expect(decoded.spelling == word.spelling)
        #expect(decoded.phonetic == word.phonetic)
        #expect(decoded.sentiment == word.sentiment)
        #expect(decoded.frequency == word.frequency)
        #expect(decoded.definitions.count == 1)
        #expect(decoded.mnemonics.first == "一朝之花")
    }

    @Test("ReviewCard default initialization")
    func testReviewCardDefaults() {
        let card = ReviewCard(wordId: "test")
        #expect(card.state == .new)
        #expect(card.stability == 0)
        #expect(card.difficulty == 5.0)
        #expect(card.reps == 0)
        #expect(card.lapses == 0)
    }

    @Test("FrequencyTier comparison")
    func testFrequencyTierComparison() {
        #expect(FrequencyTier.core < FrequencyTier.common)
        #expect(FrequencyTier.common < FrequencyTier.advanced)
    }
}
