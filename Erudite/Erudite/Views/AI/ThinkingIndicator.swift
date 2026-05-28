import SwiftUI

// MARK: - Thinking Indicator

/// Shows an animated indicator when the AI is executing a tool.
struct ThinkingIndicator: View {
    let toolName: String?
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "gear")
                .font(.caption)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(rotation))

            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .task {
            // Animate gear rotation
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                rotation += 5
            }
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
