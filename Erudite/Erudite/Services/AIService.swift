import Foundation

// MARK: - AI Service
// High-level AI capabilities built on top of AIProvider.

@MainActor
final class AIService {
    private let provider: AIProvider

    init(provider: AIProvider? = nil) {
        self.provider = provider ?? ClaudeProvider()
    }

    // MARK: - Per-Word

    /// Generate a personalized mnemonic for a word
    func generateMnemonic(word: Word) async throws -> String {
        let prompt = """
        Generate a memorable mnemonic for the GRE word "\(word.spelling)" (\(word.definitions.first?.english ?? "")).
        Connect it to Chinese if possible. Keep it concise (1-2 sentences).
        """
        return try await provider.generate(prompt: prompt, system: "You are a GRE vocabulary tutor.")
    }

    /// Generate a GRE-style example sentence
    func generateExample(word: Word) async throws -> String {
        let prompt = """
        Create a GRE-style example sentence using the word "\(word.spelling)" (\(word.definitions.first?.english ?? "")).
        The sentence should demonstrate the word's meaning clearly in an academic context.
        """
        return try await provider.generate(prompt: prompt, system: "You are a GRE vocabulary tutor.")
    }

    /// Compare two similar words
    func compareWords(_ wordA: Word, _ wordB: Word) async throws -> String {
        let prompt = """
        Compare the GRE words "\(wordA.spelling)" and "\(wordB.spelling)".
        Explain the key differences in meaning, usage, and connotation.
        Keep it concise (3-4 sentences).
        """
        return try await provider.generate(prompt: prompt, system: "You are a GRE vocabulary tutor.")
    }

    // MARK: - Per-Session

    /// Generate a daily briefing
    func generateDailyBriefing(
        dueCount: Int,
        newCount: Int,
        weakWords: [String]
    ) async throws -> String {
        let prompt = """
        Generate a brief daily study plan summary:
        - Due reviews: \(dueCount)
        - New words today: \(newCount)
        - Weak areas: \(weakWords.joined(separator: ", "))
        Keep it to 2-3 sentences, encouraging tone.
        """
        return try await provider.generate(prompt: prompt, system: "You are a GRE vocabulary tutor.")
    }

    /// Generate a session summary
    func generateSessionSummary(
        studied: Int,
        accuracy: Double,
        weakWords: [String]
    ) async throws -> String {
        let prompt = """
        Summarize a study session:
        - Words studied: \(studied)
        - Accuracy: \(Int(accuracy * 100))%
        - Struggled with: \(weakWords.joined(separator: ", "))
        Give brief encouragement and one suggestion. 2-3 sentences.
        """
        return try await provider.generate(prompt: prompt, system: "You are a GRE vocabulary tutor.")
    }
}
