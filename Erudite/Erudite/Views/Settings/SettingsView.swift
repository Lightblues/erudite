import SwiftUI

// MARK: - Settings View
//
// macOS Settings scene (⌘,) — two tabs that map directly to AppConfig.shared.
// Edits are written immediately on field commit (didSet on AppConfig persists
// to Keychain or UserDefaults), so there's no Save button — closing the
// window is enough.
struct SettingsView: View {
    var body: some View {
        TabView {
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
            DictionarySettingsTab()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - AI tab

private struct AISettingsTab: View {
    // We bind directly to the @Observable singleton so writes propagate
    // everywhere instantly (including the AI-disabled overlay).
    @Bindable private var config = AppConfig.shared

    @State private var apiKeyDraft = ""
    @State private var baseURLDraft = ""
    @State private var modelDraft = ""
    @State private var fastModelDraft = ""
    @State private var revealKey = false
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("API Key") {
                    HStack(spacing: 6) {
                        keyField
                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealKey ? "Hide" : "Show")

                        Button {
                            if let s = NSPasteboard.general.string(forType: .string) {
                                apiKeyDraft = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                commitKey()
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .help("Paste from clipboard")
                    }
                }
            } header: {
                Text("Anthropic / Claude-compatible endpoint")
                    .font(.headline)
            } footer: {
                Text("Used by the AI Companion and background tasks. Stored in macOS Keychain on this Mac only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Base URL") {
                    TextField("https://api.anthropic.com/v1/messages", text: $baseURLDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitBaseURL() }
                }
                LabeledContent("Model") {
                    TextField(AnthropicModel.sonnet, text: $modelDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitModel() }
                }
                LabeledContent("Fast Model") {
                    TextField("falls back to Model, then Haiku", text: $fastModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitFastModel() }
                }
            } header: {
                Text("Optional overrides")
                    .font(.subheadline)
            } footer: {
                Text("Leave blank to use defaults. Proxies / OpenAI-compatible gateways: set Base URL to your endpoint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack(spacing: 6) {
                            if testState == .running {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.horizontal")
                            }
                            Text(testState == .running ? "Testing…" : "Test Connection")
                        }
                    }
                    .disabled(apiKeyDraft.isEmpty || testState == .running)

                    Spacer()

                    statusLabel
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: loadDrafts)
        // Persist on focus changes too so blur-without-Enter still saves.
        .onChange(of: baseURLDraft) { _, _ in commitBaseURL() }
        .onChange(of: modelDraft) { _, _ in commitModel() }
        .onChange(of: fastModelDraft) { _, _ in commitFastModel() }
    }

    @ViewBuilder
    private var keyField: some View {
        if revealKey {
            TextField("sk-ant-…", text: $apiKeyDraft, onCommit: commitKey)
                .textFieldStyle(.roundedBorder)
        } else {
            SecureField("sk-ant-…", text: $apiKeyDraft, onCommit: commitKey)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .running:
            EmptyView()
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
                .help(msg)
        }
    }

    // MARK: - Commit / load

    private func loadDrafts() {
        apiKeyDraft = config.aiApiKey
        baseURLDraft = config.aiBaseURL ?? ""
        modelDraft = config.aiModel ?? ""
        fastModelDraft = config.aiFastModel ?? ""
    }

    private func commitKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != config.aiApiKey { config.aiApiKey = trimmed }
        testState = .idle
    }

    private func commitBaseURL() {
        let trimmed = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        if value != config.aiBaseURL { config.aiBaseURL = value }
    }

    private func commitModel() {
        let trimmed = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        if value != config.aiModel { config.aiModel = value }
    }

    private func commitFastModel() {
        let trimmed = fastModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        if value != config.aiFastModel { config.aiFastModel = value }
    }

    // MARK: - Test connection

    private func runTest() async {
        commitKey(); commitBaseURL(); commitModel(); commitFastModel()
        guard !config.aiApiKey.isEmpty else { return }
        testState = .running

        do {
            let ok = try await SettingsConnectionTest.testAnthropic(
                apiKey: config.aiApiKey,
                baseURL: config.resolvedAIBaseURL,
                model: config.resolvedFastModel
            )
            testState = ok ? .success("Connected") : .failure("Empty response")
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Dictionary tab

private struct DictionarySettingsTab: View {
    @Bindable private var config = AppConfig.shared

    @State private var collDraft = ""
    @State private var thesDraft = ""
    @State private var revealColl = false
    @State private var revealThes = false
    @State private var testState: AISettingsTab.TestState = .idle

    var body: some View {
        Form {
            Section {
                LabeledContent("Collegiate Key") {
                    HStack(spacing: 6) {
                        keyField($collDraft, reveal: revealColl, onCommit: commitColl)
                        Button { revealColl.toggle() } label: {
                            Image(systemName: revealColl ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                LabeledContent("Thesaurus Key") {
                    HStack(spacing: 6) {
                        keyField($thesDraft, reveal: revealThes, onCommit: commitThes)
                        Button { revealThes.toggle() } label: {
                            Image(systemName: revealThes ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Merriam-Webster")
                    .font(.headline)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optional. When both keys are set, MW is used for richer entries (etymology, examples, thesaurus). Otherwise we fall back to a free public API.")
                    Link("Get free API keys from dictionaryapi.com",
                         destination: URL(string: "https://dictionaryapi.com/register/index")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack(spacing: 6) {
                            if testState == .running {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.horizontal")
                            }
                            Text(testState == .running ? "Testing…" : "Test Lookup")
                        }
                    }
                    .disabled(collDraft.isEmpty || testState == .running)

                    Spacer()

                    switch testState {
                    case .idle: EmptyView()
                    case .running: EmptyView()
                    case .success(let m):
                        Label(m, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                    case .failure(let m):
                        Label(m, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red).font(.caption)
                            .lineLimit(2).help(m)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            collDraft = config.mwDictionaryKey
            thesDraft = config.mwThesaurusKey
        }
    }

    @ViewBuilder
    private func keyField(_ binding: Binding<String>, reveal: Bool, onCommit: @escaping () -> Void) -> some View {
        if reveal {
            TextField("API key", text: binding, onCommit: onCommit)
                .textFieldStyle(.roundedBorder)
        } else {
            SecureField("API key", text: binding, onCommit: onCommit)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func commitColl() {
        let v = collDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if v != config.mwDictionaryKey { config.mwDictionaryKey = v }
        testState = .idle
    }

    private func commitThes() {
        let v = thesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if v != config.mwThesaurusKey { config.mwThesaurusKey = v }
        testState = .idle
    }

    private func runTest() async {
        commitColl(); commitThes()
        guard !config.mwDictionaryKey.isEmpty else { return }
        testState = .running
        do {
            let ok = try await SettingsConnectionTest.testMerriamWebster(
                key: config.mwDictionaryKey,
                probe: "test"
            )
            testState = ok ? .success("OK") : .failure("Key rejected")
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Connection probes
//
// Tiny one-shot HTTP probes used by the test buttons. Kept here (not in
// production AI/dictionary services) because they're UI-only and don't
// share retry/streaming/parsing logic.
enum SettingsConnectionTest {
    /// POST 1-token completion. Returns true on HTTP 200, throws otherwise.
    static func testAnthropic(apiKey: String, baseURL: String, model: String) async throws -> Bool {
        guard let url = URL(string: baseURL) else {
            throw NSError(domain: "Settings", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Base URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if baseURL.contains("anthropic.com") {
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        } else {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 15
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 200 { return true }
        // Pull a useful error message out of the response body.
        let msg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any],
           let m = err["message"] as? String {
            msg = m
        } else {
            msg = "HTTP \(http.statusCode)"
        }
        throw NSError(domain: "Settings", code: http.statusCode,
                      userInfo: [NSLocalizedDescriptionKey: msg])
    }

    /// GET MW collegiate for a simple word. Body is a JSON array on success.
    static func testMerriamWebster(key: String, probe: String) async throws -> Bool {
        let encoded = probe.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? probe
        guard let url = URL(string: "https://dictionaryapi.com/api/v3/references/collegiate/json/\(encoded)?key=\(key)") else {
            return false
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode != 200 {
            throw NSError(domain: "Settings", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        // MW returns a JSON array — either of entries (key valid) or of
        // suggestion strings (key valid, word unknown). An invalid key
        // yields a plain text error message, which fails JSON parse.
        guard let _ = try? JSONSerialization.jsonObject(with: data) else {
            throw NSError(domain: "Settings", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Key rejected by MW"])
        }
        return true
    }
}

#Preview {
    SettingsView()
}
