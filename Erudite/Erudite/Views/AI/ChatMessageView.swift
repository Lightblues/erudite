import SwiftUI

// MARK: - Chat Message View

/// Renders a single chat message (user or assistant).
struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Tool use indicator
                if message.hasToolUse {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption2)
                        Text("Used: \(message.toolNames.joined(separator: ", "))")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                // Message content
                if !message.text.isEmpty {
                    markdownText(message.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, message.role == .user ? 8 : 0)
        .background(
            message.role == .user
                ? AnyShapeStyle(.blue.opacity(0.06))
                : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .font(.body)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
