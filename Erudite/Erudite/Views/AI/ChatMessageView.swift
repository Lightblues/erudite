import SwiftUI

// MARK: - Chat Message View

/// Renders a single chat message (user or assistant).
struct ChatMessageView: View {
    let message: ChatMessage
    @State private var showToolDetails = false

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
                // Tool use details (collapsible)
                if message.hasToolUse {
                    toolCallSection
                }

                // Message content
                if !message.text.isEmpty {
                    markdownText(message.text)
                }

                // Turn metadata (tokens, latency, request ID)
                if let meta = message.turnMeta {
                    turnMetaView(meta)
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

    // MARK: - Tool Call Section

    private var toolCallSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Clickable header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showToolDetails.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showToolDetails ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption2)
                    Text(toolCallSummary)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Expanded details
            if showToolDetails {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(toolCallDetails, id: \.id) { detail in
                        toolDetailRow(detail)
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 2)
            }
        }
    }

    private var toolCallSummary: String {
        let names = message.toolNames
        if names.count == 1 {
            return "Called \(names[0])"
        }
        return "Called \(names.count) tools"
    }

    private struct ToolCallDetail: Identifiable {
        let id: String
        let name: String
        let input: String
        let result: String?
    }

    private var toolCallDetails: [ToolCallDetail] {
        // Extract tool_use blocks and pair with their results
        var details: [ToolCallDetail] = []

        for block in message.blocks {
            if case .toolUse(let id, let name, let input) = block {
                let inputStr = formatJSON(input)
                // Find matching tool_result in subsequent messages (if available)
                let resultStr = findToolResult(for: id)
                details.append(ToolCallDetail(id: id, name: name, input: inputStr, result: resultStr))
            }
        }
        return details
    }

    private func toolDetailRow(_ detail: ToolCallDetail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Tool name
            Text("→ \(detail.name)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.orange)

            // Input params
            if !detail.input.isEmpty && detail.input != "{}" {
                Text("  input: \(detail.input)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Result
            if let result = detail.result {
                Text("  → \(result)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.8))
                    .textSelection(.enabled)
                    .lineLimit(8)
            }
        }
    }

    private func findToolResult(for toolUseId: String) -> String? {
        // Look through all messages in the runtime to find the tool_result
        // This is a simplified approach — we check the message's own blocks first
        // (in case of inline results), then check the global message list via AppState
        guard let runtime = AppState.shared.aiRuntime else { return nil }

        for msg in runtime.messages where msg.isToolResult {
            for block in msg.blocks {
                if case .toolResult(let id, let content, _) = block, id == toolUseId {
                    return content
                }
            }
        }
        return nil
    }

    private func formatJSON(_ value: JSONValue) -> String {
        switch value {
        case .object(let dict) where dict.isEmpty:
            return "{}"
        case .object(let dict):
            let pairs = dict.map { key, val in
                "\(key): \(formatJSONValue(val))"
            }
            return "{ \(pairs.joined(separator: ", ")) }"
        default:
            return formatJSONValue(value)
        }
    }

    private func formatJSONValue(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return "\"\(s)\""
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let arr): return "[\(arr.map { formatJSONValue($0) }.joined(separator: ", "))]"
        case .object(let dict): return formatJSON(.object(dict))
        }
    }

    // MARK: - Turn Metadata

    private func turnMetaView(_ meta: TurnMeta) -> some View {
        HStack(spacing: 8) {
            // Tokens
            Text("\(meta.inputTokens)→\(meta.outputTokens) tok")
            // Latency
            Text("\(meta.latencyMs)ms")
            // Cache
            if meta.cacheHit {
                Text("cache✓")
                    .foregroundStyle(.green)
            }
            // Request ID (truncated)
            if let rid = meta.requestId {
                Text(String(rid.prefix(8)))
                    .help("Request ID: \(rid)")
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.secondary.opacity(0.7))
        .padding(.top, 2)
    }

    // MARK: - Markdown

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
