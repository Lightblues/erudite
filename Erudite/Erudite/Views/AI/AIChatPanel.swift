import SwiftUI

// MARK: - AI Chat Panel

/// Fixed right-side panel containing the AI chat companion.
struct AIChatPanel: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ChatViewModel
    @State private var showSessionList = false

    init(runtime: AgentRuntime) {
        self._viewModel = State(initialValue: ChatViewModel(runtime: runtime))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader

            Divider()

            // Content
            if viewModel.isEmpty && !viewModel.isProcessing {
                emptyState
            } else {
                messageList
            }

            // Error banner
            if viewModel.hasError {
                errorBanner
            }

            Divider()

            // Input (always editable — even during streaming)
            ChatInputView(
                text: $viewModel.inputText,
                isProcessing: viewModel.isProcessing,
                onSend: viewModel.send,
                onCancel: viewModel.cancel
            )
        }
        .background(.background)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .font(.caption)

            // Session title
            Text(appState.sessionManager?.currentSession?.title ?? "AI Companion")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // New session
            Button {
                createNewSession()
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("New conversation")

            // Session list
            Button {
                showSessionList.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Conversation history")
            .popover(isPresented: $showSessionList) {
                SessionListView(
                    sessions: appState.sessionManager?.sessions ?? [],
                    currentSessionId: appState.sessionManager?.currentSession?.id,
                    onSelect: { switchToSession($0) },
                    onDelete: { deleteSession($0) },
                    onNewSession: { createNewSession() }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Session Actions

    private func createNewSession() {
        guard let sessionManager = appState.sessionManager,
              let runtime = appState.aiRuntime else { return }
        // Flush memory before switching
        appState.flushMemory()
        _ = try? sessionManager.createNewSession()
        runtime.clearHistory()
        appState.memoryStore?.resetWatermark()
    }

    private func switchToSession(_ id: String) {
        guard let sessionManager = appState.sessionManager,
              let runtime = appState.aiRuntime else { return }
        appState.flushMemory()
        if let messages = try? sessionManager.switchToSession(id: id) {
            runtime.loadMessages(messages)
        }
        appState.memoryStore?.resetWatermark()
        showSessionList = false
    }

    private func deleteSession(_ id: String) {
        guard let sessionManager = appState.sessionManager else { return }
        try? sessionManager.deleteSession(id: id)
        sessionManager.refreshSessionList()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.purple.opacity(0.5))
            Text("Ask me anything about\nyour vocabulary learning")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 6) {
                suggestionButton("How am I doing?")
                suggestionButton("What words should I focus on?")
                suggestionButton("Help me remember 'aberrant'")
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding()
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            viewModel.inputText = text
            viewModel.send()
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Message List

    private var messageList: some View {
        // Use runtime.messages directly with ForEach + filter in the view body
        // to avoid creating new array on each evaluation (which causes infinite re-render)
        let messages = appState.aiRuntime?.messages ?? []

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages, id: \.id) { message in
                        if !message.isToolResult {
                            ChatMessageView(message: message)
                                .id(message.id)
                        }
                    }

                    // Streaming text (in-progress)
                    if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                        StreamingTextView(text: viewModel.streamingText)
                            .id("streaming")
                    }

                    // Tool execution indicator
                    if viewModel.isExecutingTool {
                        ThinkingIndicator(toolName: viewModel.executingToolName)
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.streamingText) { _, newText in
                // Only auto-scroll during active streaming
                if viewModel.isStreaming && !newText.isEmpty {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messageCount) { _, _ in
                // Scroll to bottom when new message arrives
                if let last = messages.last(where: { !$0.isToolResult }) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Error Banner

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(viewModel.errorMessage ?? "Unknown error")
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Dismiss") {
                viewModel.dismissError()
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.08))
    }
}
