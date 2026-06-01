import Foundation

// MARK: - Agent Runtime

/// Orchestrates the multi-turn tool-use loop between the user, LLM, and tools.
/// This is the core "brain" of the AI companion — it manages the conversation,
/// streams responses, and dispatches tool calls.
@Observable
final class AgentRuntime {

    // MARK: - State

    enum Phase: Equatable {
        case idle
        case streaming
        case toolExecution(String)  // tool name being executed
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.streaming, .streaming): return true
            case (.toolExecution(let a), .toolExecution(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var streamingText: String = ""
    private(set) var messages: [ChatMessage] = []

    // Usage tracking
    private(set) var totalInputTokens: Int = 0
    private(set) var totalOutputTokens: Int = 0
    private(set) var cacheHits: Int = 0

    // MARK: - Dependencies

    private let client: AnthropicClient
    private let toolRegistry: ToolRegistry
    private let db: DatabaseService
    private var currentTask: Task<Void, Never>?

    // Configuration
    private let maxToolRounds = 10
    private let maxTokens = 2048

    // MARK: - Init

    init(client: AnthropicClient, db: DatabaseService) {
        self.client = client
        self.toolRegistry = .shared
        self.db = db
    }

    // MARK: - Public API

    /// Callback after each complete turn (all new messages since last save).
    /// Called with the full messages array — persistence layer saves any unsaved ones.
    var onTurnComplete: ((_ allMessages: [ChatMessage]) -> Void)?

    /// Load pre-existing messages (from session restore).
    func loadMessages(_ restoredMessages: [ChatMessage]) {
        messages = restoredMessages
    }

    /// Send a user message and run the agent loop.
    func send(userMessage: String) {
        let msg = ChatMessage(role: .user, text: userMessage)
        messages.append(msg)

        currentTask?.cancel()
        currentTask = Task { await runAgentLoop() }
    }

    /// Cancel in-flight generation.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        if phase != .idle {
            phase = .idle
        }
    }

    /// Clear all conversation history.
    func clearHistory() {
        cancel()
        messages.removeAll()
        streamingText = ""
        totalInputTokens = 0
        totalOutputTokens = 0
        cacheHits = 0
    }

    var isProcessing: Bool {
        switch phase {
        case .streaming, .toolExecution: return true
        default: return false
        }
    }

    // MARK: - Agent Loop

    private func runAgentLoop() async {
        var toolRounds = 0

        while toolRounds < maxToolRounds {
            guard !Task.isCancelled else {
                phase = .idle
                return
            }

            streamingText = ""
            phase = .streaming

            do {
                let request = buildRequest()
                let apiKey = AppConfig.shared.aiApiKey

                guard AppConfig.shared.hasAIKey else {
                    phase = .error("API key not configured. Open Settings (⌘,) to add your Anthropic key.")
                    return
                }

                let startTime = ContinuousClock.now
                Log.ai.info("API request: model=\(request.model), messages=\(messages.count)")

                let (stream, requestId) = try await client.stream(
                    request: request,
                    apiKey: apiKey,
                    baseURL: AppConfig.shared.resolvedAIBaseURL
                )
                if let requestId {
                    Log.ai.debug("Request ID: \(requestId)")
                }

                var accumulatedText = ""
                var toolCalls: [PendingToolCall] = []
                var currentToolCall: PendingToolCall?
                var lastUIUpdate = ContinuousClock.now
                var turnInputTokens = 0
                var turnOutputTokens = 0
                var turnCacheHit = false
                let uiUpdateInterval: Duration = .milliseconds(50) // Throttle: max 20 UI updates/sec

                for try await event in stream {
                    guard !Task.isCancelled else {
                        phase = .idle
                        return
                    }

                    switch event {
                    case .messageStart(let payload):
                        if let usage = payload.message.usage {
                            turnInputTokens += usage.input_tokens ?? 0
                            totalInputTokens += usage.input_tokens ?? 0
                            if let cacheRead = usage.cache_read_input_tokens, cacheRead > 0 {
                                turnCacheHit = true
                                cacheHits += 1
                            }
                        }

                    case .contentBlockStart(_, let block):
                        if block.type == "tool_use" {
                            currentToolCall = PendingToolCall(
                                id: block.id ?? UUID().uuidString,
                                name: block.name ?? "unknown",
                                inputJSON: ""
                            )
                        }

                    case .contentBlockDelta(_, let delta):
                        switch delta {
                        case .textDelta(let text):
                            accumulatedText += text
                            // Throttle UI updates to avoid excessive re-renders
                            let now = ContinuousClock.now
                            if now - lastUIUpdate >= uiUpdateInterval {
                                streamingText = accumulatedText
                                lastUIUpdate = now
                            }
                        case .inputJSONDelta(let partial):
                            currentToolCall?.inputJSON += partial
                        }

                    case .contentBlockStop:
                        if let tc = currentToolCall {
                            toolCalls.append(tc)
                            currentToolCall = nil
                        }
                        // Flush text on block stop (ensures final text is shown)
                        if !accumulatedText.isEmpty {
                            streamingText = accumulatedText
                        }

                    case .messageDelta(_, let usage):
                        if let usage {
                            turnOutputTokens += usage.output_tokens ?? 0
                            totalOutputTokens += usage.output_tokens ?? 0
                        }

                    case .messageStop, .ping:
                        break

                    case .error(let apiError):
                        Log.ai.error("API error in stream", error: apiError)
                        phase = .error(apiError.message)
                        return
                    }
                }

                // Stream ended — process results

                if toolCalls.isEmpty {
                    // Pure text response — done
                    let elapsed = startTime.duration(to: .now)
                    let latencyMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                    Log.ai.info("Response complete: \(latencyMs)ms, in=\(turnInputTokens) out=\(turnOutputTokens)")

                    let meta = TurnMeta(
                        requestId: requestId,
                        model: request.model,
                        inputTokens: turnInputTokens,
                        outputTokens: turnOutputTokens,
                        cacheHit: turnCacheHit,
                        latencyMs: latencyMs,
                        toolCalls: toolCalls.map(\.name) // empty here, but included for consistency
                    )

                    AITracer.shared.record(
                        model: request.model,
                        purpose: "chat",
                        inputTokens: turnInputTokens,
                        outputTokens: turnOutputTokens,
                        cacheHit: turnCacheHit,
                        latencyMs: latencyMs,
                        sessionId: AppState.shared.sessionManager?.currentSession?.id
                    )

                    var assistantMsg = ChatMessage(role: .assistant, text: accumulatedText)
                    assistantMsg.turnMeta = meta
                    messages.append(assistantMsg)
                    streamingText = ""
                    phase = .idle

                    // Notify for persistence + memory extraction
                    onTurnComplete?(messages)
                    return

                } else {
                    // Tool use: append assistant message with tool calls
                    var blocks: [ContentBlock] = []
                    if !accumulatedText.isEmpty {
                        blocks.append(.text(accumulatedText))
                    }
                    for tc in toolCalls {
                        let input = parseToolInput(tc.inputJSON)
                        blocks.append(.toolUse(id: tc.id, name: tc.name, input: input))
                    }
                    messages.append(ChatMessage(role: .assistant, text: accumulatedText, blocks: blocks))

                    // Execute tools
                    var resultBlocks: [ContentBlock] = []
                    for tc in toolCalls {
                        phase = .toolExecution(tc.name)
                        let input = parseToolInput(tc.inputJSON)
                        let inputDict: [String: JSONValue]
                        if let obj = input.objectValue {
                            inputDict = obj
                        } else {
                            inputDict = [:]
                        }

                        do {
                            let result = try toolRegistry.execute(name: tc.name, input: inputDict, db: db)
                            resultBlocks.append(.toolResult(toolUseId: tc.id, content: result, isError: false))
                        } catch {
                            resultBlocks.append(.toolResult(toolUseId: tc.id, content: "Error: \(error.localizedDescription)", isError: true))
                        }
                    }

                    // Append tool results as user message (per Anthropic API spec)
                    messages.append(ChatMessage(role: .user, text: "", blocks: resultBlocks, isToolResult: true))
                    toolRounds += 1

                    // Inject "stop looping" hint when approaching limit
                    if toolRounds >= maxToolRounds - 2 {
                        let hintBlock: [ContentBlock] = [.text("[System: You have used many tool calls. Please respond directly to the user now without calling more tools.]")]
                        messages.append(ChatMessage(role: .user, text: "", blocks: hintBlock, isToolResult: true))
                    }

                    // Loop continues — sends updated messages back to LLM
                }

            } catch is CancellationError {
                phase = .idle
                return
            } catch {
                phase = .error(error.localizedDescription)
                return
            }
        }

        // Exceeded max tool rounds
        let fallback = ChatMessage(role: .assistant, text: streamingText + "\n\n_(Stopped: reached tool call limit)_")
        messages.append(fallback)
        streamingText = ""
        phase = .idle
    }

    // MARK: - Helpers

    private func buildRequest() -> AnthropicRequest {
        let systemPrompt = SystemPrompt.build(
            currentTab: AppState.shared.selectedTab,
            memoryStore: AppState.shared.memoryStore
        )

        // Convert messages to API format
        let apiMessages = messages.map { $0.toAPIMessage() }

        return AnthropicRequest(
            model: AppConfig.shared.resolvedAIModel,
            max_tokens: maxTokens,
            system: [
                AnthropicRequest.SystemBlock(text: systemPrompt, cacheControl: true)
            ],
            messages: apiMessages,
            tools: toolRegistry.definitions,
            stream: true
        )
    }

    private func parseToolInput(_ json: String) -> JSONValue {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }
}

// MARK: - Supporting Types

private struct PendingToolCall {
    let id: String
    let name: String
    var inputJSON: String
}

// MARK: - Turn Metadata

/// Metadata about an LLM turn (attached to assistant messages)
struct TurnMeta {
    let requestId: String?
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheHit: Bool
    let latencyMs: Int
    let toolCalls: [String]
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    let text: String
    let blocks: [ContentBlock]
    let isToolResult: Bool
    let timestamp: Date
    var turnMeta: TurnMeta?  // Only set on final assistant messages

    /// Simple text message
    init(role: MessageRole, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.blocks = [.text(text)]
        self.isToolResult = false
        self.timestamp = Date()
    }

    /// Message with explicit content blocks (tool use / tool results)
    init(role: MessageRole, text: String, blocks: [ContentBlock], isToolResult: Bool = false) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.blocks = blocks
        self.isToolResult = isToolResult
        self.timestamp = Date()
    }

    /// Restore from persistence (with existing id and timestamp)
    init(id: UUID, role: MessageRole, text: String, blocks: [ContentBlock], isToolResult: Bool, timestamp: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.blocks = blocks
        self.isToolResult = isToolResult
        self.timestamp = timestamp
    }

    /// Convert to API wire format
    func toAPIMessage() -> APIMessage {
        APIMessage(role: role, content: blocks)
    }

    /// Whether this message contains tool use calls (shown as indicator in UI)
    var hasToolUse: Bool {
        blocks.contains { block in
            if case .toolUse = block { return true }
            return false
        }
    }

    /// Tool names used in this message
    var toolNames: [String] {
        blocks.compactMap { block in
            if case .toolUse(_, let name, _) = block { return name }
            return nil
        }
    }
}
