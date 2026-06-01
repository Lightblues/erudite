import Foundation
import Observation

// MARK: - App Configuration
//
// Single source of truth for API keys and AI endpoint config. Edits made
// through SettingsView are immediately visible to every reader because this
// is a shared @Observable class.
//
// Storage layout:
//   - Secrets (API keys)              → Keychain   (encrypted, survives reinstall)
//   - Non-secret prefs (URL / models) → UserDefaults
//
// Local-only: nothing is synced via iCloud. Users move between machines via
// the upcoming Settings → Backup export/import flow.
@Observable
final class AppConfig {
    /// Shared singleton — read by DictionaryAPIService, AnthropicClient,
    /// BackgroundAI, AgentRuntime. Written by SettingsView.
    static let shared = AppConfig()

    // MARK: - Secrets (Keychain-backed)

    var mwDictionaryKey: String {
        didSet { KeychainStore.set(mwDictionaryKey, for: Keys.mwDictionaryKey) }
    }
    var mwThesaurusKey: String {
        didSet { KeychainStore.set(mwThesaurusKey, for: Keys.mwThesaurusKey) }
    }
    var aiApiKey: String {
        didSet { KeychainStore.set(aiApiKey, for: Keys.aiApiKey) }
    }

    // MARK: - Non-secret preferences (UserDefaults-backed)
    //
    // Kept Optional<String> so existing call-sites that read e.g.
    // `aiBaseURL` as `String?` keep working unchanged. Empty stored value
    // is normalized to nil so the resolved* fallbacks fire.

    var aiBaseURL: String? {
        didSet { UserDefaults.standard.set(aiBaseURL ?? "", forKey: Keys.aiBaseURL) }
    }
    var aiModel: String? {
        didSet { UserDefaults.standard.set(aiModel ?? "", forKey: Keys.aiModel) }
    }
    var aiFastModel: String? {
        didSet { UserDefaults.standard.set(aiFastModel ?? "", forKey: Keys.aiFastModel) }
    }

    // MARK: - Init

    private init() {
        self.mwDictionaryKey = KeychainStore.get(Keys.mwDictionaryKey) ?? ""
        self.mwThesaurusKey = KeychainStore.get(Keys.mwThesaurusKey) ?? ""
        self.aiApiKey = KeychainStore.get(Keys.aiApiKey) ?? ""

        let defaults = UserDefaults.standard
        self.aiBaseURL  = (defaults.string(forKey: Keys.aiBaseURL)).flatMap  { $0.isEmpty ? nil : $0 }
        self.aiModel    = (defaults.string(forKey: Keys.aiModel)).flatMap   { $0.isEmpty ? nil : $0 }
        self.aiFastModel = (defaults.string(forKey: Keys.aiFastModel)).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Derived state

    /// Whether Merriam-Webster is configured (both keys non-empty).
    var hasMWKeys: Bool {
        !mwDictionaryKey.isEmpty && !mwThesaurusKey.isEmpty
    }

    /// Whether AI API is configured.
    var hasAIKey: Bool { !aiApiKey.isEmpty }

    /// Resolved base URL (defaults to Anthropic official endpoint).
    var resolvedAIBaseURL: String {
        if let url = aiBaseURL, !url.isEmpty {
            return url.hasSuffix("/") ? String(url.dropLast()) : url
        }
        return "https://api.anthropic.com/v1/messages"
    }

    /// Resolved model name (defaults to Sonnet).
    var resolvedAIModel: String {
        if let model = aiModel, !model.isEmpty { return model }
        return AnthropicModel.sonnet
    }

    /// Resolved fast model — falls back to main model, then to Haiku.
    /// (User's proxy may not support haiku; main-model fallback keeps
    /// background tasks alive.)
    var resolvedFastModel: String {
        if let model = aiFastModel, !model.isEmpty { return model }
        if let model = aiModel, !model.isEmpty { return model }
        return AnthropicModel.haiku
    }

    // MARK: - Storage keys

    private enum Keys {
        // Keychain account names
        static let mwDictionaryKey = "mwDictionaryKey"
        static let mwThesaurusKey = "mwThesaurusKey"
        static let aiApiKey = "aiApiKey"
        // UserDefaults keys
        static let aiBaseURL = "config.aiBaseURL"
        static let aiModel = "config.aiModel"
        static let aiFastModel = "config.aiFastModel"
    }
}
