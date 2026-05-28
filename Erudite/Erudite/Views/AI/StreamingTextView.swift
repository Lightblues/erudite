import SwiftUI

// MARK: - Streaming Text View

/// Displays in-progress streaming text with a blinking cursor.
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

            VStack(alignment: .leading) {
                let cursor = cursorVisible ? " ▊" : "  "
                if let attributed = try? AttributedString(
                    markdown: text + cursor,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                    )
                ) {
                    Text(attributed)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    Text(text + cursor)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .task {
            // Blink cursor
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                cursorVisible.toggle()
            }
        }
    }
}
