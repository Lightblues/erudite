import Foundation

// MARK: - App Configuration

/// Loads API keys and configuration from Config.json (bundle resource, git-ignored).
/// Copy Config.example.json → Config.json and fill in your keys.
struct AppConfig: Codable {
    let mwDictionaryKey: String
    let mwThesaurusKey: String
    let aiApiKey: String
    let aiBaseURL: String?
    let aiModel: String?
    let aiFastModel: String?

    /// Whether Merriam-Webster API is configured (non-empty key)
    var hasMWKeys: Bool {
        !mwDictionaryKey.isEmpty &&
        mwDictionaryKey != "YOUR_MERRIAM_WEBSTER_COLLEGIATE_KEY"
    }

    /// Whether AI API is configured
    var hasAIKey: Bool {
        !aiApiKey.isEmpty && aiApiKey != "YOUR_AI_API_KEY_HERE"
    }

    /// Resolved base URL (defaults to Anthropic official endpoint)
    var resolvedAIBaseURL: String {
        if let url = aiBaseURL, !url.isEmpty, url != "https://api.anthropic.com/v1/messages" {
            // Strip trailing slash for consistency
            return url.hasSuffix("/") ? String(url.dropLast()) : url
        }
        return "https://api.anthropic.com/v1/messages"
    }

    /// Resolved model name (defaults to Sonnet)
    var resolvedAIModel: String {
        if let model = aiModel, !model.isEmpty {
            return model
        }
        return AnthropicModel.sonnet
    }

    /// Resolved fast model (defaults to Haiku) — used for background tasks
    var resolvedFastModel: String {
        if let model = aiFastModel, !model.isEmpty {
            return model
        }
        return AnthropicModel.haiku
    }

    /// Shared singleton loaded from bundle
    static let shared: AppConfig = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "json") else {
            print("[AppConfig] Config.json not found in bundle. Copy Config.example.json → Config.json and add your keys.")
            return AppConfig(mwDictionaryKey: "", mwThesaurusKey: "", aiApiKey: "", aiBaseURL: nil, aiModel: nil, aiFastModel: nil)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            print("[AppConfig] Failed to parse Config.json: \(error)")
            return AppConfig(mwDictionaryKey: "", mwThesaurusKey: "", aiApiKey: "", aiBaseURL: nil, aiModel: nil, aiFastModel: nil)
        }
    }()
}
