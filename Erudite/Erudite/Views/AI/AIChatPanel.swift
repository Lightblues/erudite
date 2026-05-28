import SwiftUI

// MARK: - AI Chat Panel

/// Fixed right-side panel containing the AI chat companion.
struct AIChatPanel: View {
    @State private var viewModel: ChatViewModel

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

            // Input
            ChatInputView(
                text: $viewModel.inputText,
                isProcessing: viewModel.isProcessing,
                onSend: viewModel.send,
                onCancel: viewModel.cancel
            )
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 360)
        .background(.background)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text("AI Companion")
                .font(.headline)
            Spacer()
            if !viewModel.isEmpty {
                Button(action: viewModel.clearChat) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear conversation")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.visibleMessages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
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
            .onChange(of: viewModel.streamingText) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.visibleMessages.count) { _, _ in
                if let last = viewModel.visibleMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
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
