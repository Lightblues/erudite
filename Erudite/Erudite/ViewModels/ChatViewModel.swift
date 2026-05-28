import Foundation

// MARK: - Chat View Model

/// Thin ViewModel layer over AgentRuntime, handling UI-specific concerns
/// like input state, visibility filtering, and convenience properties.
@Observable
final class ChatViewModel {

    // MARK: - UI State

    var inputText: String = ""

    // MARK: - Runtime (source of truth)

    let runtime: AgentRuntime

    init(runtime: AgentRuntime) {
        self.runtime = runtime
    }

    // MARK: - Computed Properties

    /// Messages visible in the chat UI (filters out tool_result messages)
    var visibleMessages: [ChatMessage] {
        runtime.messages.filter { !$0.isToolResult }
    }

    /// Current streaming text being generated
    var streamingText: String {
        runtime.streamingText
    }

    /// Whether the AI is currently generating
    var isStreaming: Bool {
        runtime.phase == .streaming
    }

    /// Whether the AI is executing a tool
    var isExecutingTool: Bool {
        if case .toolExecution = runtime.phase { return true }
        return false
    }

    /// Name of tool being executed (for UI indicator)
    var executingToolName: String? {
        if case .toolExecution(let name) = runtime.phase { return name }
        return nil
    }

    /// Whether the runtime is busy (streaming or executing tools)
    var isProcessing: Bool {
        runtime.isProcessing
    }

    /// Whether there's an error to display
    var hasError: Bool {
        if case .error = runtime.phase { return true }
        return false
    }

    /// Error message if any
    var errorMessage: String? {
        if case .error(let msg) = runtime.phase { return msg }
        return nil
    }

    /// Whether the chat is empty (show placeholder)
    var isEmpty: Bool {
        runtime.messages.isEmpty
    }

    // MARK: - Actions

    /// Send the current input text
    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        runtime.send(userMessage: text)
    }

    /// Cancel current generation
    func cancel() {
        runtime.cancel()
    }

    /// Clear all chat history
    func clearChat() {
        runtime.clearHistory()
    }

    /// Dismiss error state
    func dismissError() {
        runtime.cancel()
    }
}
