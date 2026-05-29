import SwiftUI

// MARK: - Chat Input View

/// Text input field with send/cancel button. Auto-focuses when panel is active.
struct ChatInputView: View {
    @Binding var text: String
    let isProcessing: Bool
    let shouldFocus: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask anything...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }
                .disabled(isProcessing)

            if isProcessing {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Stop generating")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(canSend ? .blue : .gray.opacity(0.5))
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .help("Send message (⏎)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear {
            // Auto-focus on appear
            isFocused = true
        }
        .onChange(of: shouldFocus) { _, newValue in
            // Re-focus after streaming ends
            if newValue {
                isFocused = true
            }
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
