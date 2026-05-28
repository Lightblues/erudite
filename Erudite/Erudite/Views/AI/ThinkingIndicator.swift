import SwiftUI

// MARK: - Thinking Indicator

/// Shows an animated indicator when the AI is executing a tool.
struct ThinkingIndicator: View {
    let toolName: String?
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "gear")
                .font(.caption)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: 2).repeatForever(autoreverses: false),
                    value: isAnimating
                )

            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .onAppear {
            isAnimating = true
        }
    }

    private var displayText: String {
        if let name = toolName {
            let readable = name
                .replacingOccurrences(of: "get_", with: "")
                .replacingOccurrences(of: "_", with: " ")
            return "Looking up \(readable)..."
        }
        return "Thinking..."
    }
}
