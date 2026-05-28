import SwiftUI

// MARK: - Streaming Text View

/// Displays in-progress streaming text with a blinking cursor.
/// Uses plain text during streaming for performance (no markdown re-parse per frame).
struct StreamingTextView: View {
    let text: String
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            // Use plain Text during streaming — markdown re-parse is expensive
            Text(text + (cursorVisible ? " ▊" : ""))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                cursorVisible.toggle()
            }
        }
    }
}
