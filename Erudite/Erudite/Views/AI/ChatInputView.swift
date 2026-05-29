import SwiftUI

// MARK: - Chat Input View

/// Text input field with send/cancel button.
/// Receives focus via `focusTrigger` (toggled externally, e.g. by "/" shortcut).
/// Shift+Enter for newline, Enter to send.
/// Always editable — even during streaming (user can prepare next message).
struct ChatInputView: View {
    @Binding var text: String
    let isProcessing: Bool
    @Binding var focusTrigger: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 20, maxHeight: 100)
                .fixedSize(horizontal: false, vertical: true)
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { keyPress in
                    if keyPress.modifiers.contains(.shift) {
                        // Shift+Enter: insert newline
                        return .ignored
                    } else {
                        // Enter: send (only if not processing and has text)
                        if canSend && !isProcessing {
                            onSend()
                        }
                        return .handled
                    }
                }

            if isProcessing {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Stop generating (then send)")
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
        .padding(.vertical, 8)
        .onAppear {
            isFocused = true
        }
        .onChange(of: focusTrigger) { _, _ in
            // External focus request (e.g. "/" shortcut, session switch)
            isFocused = true
        }
        .onChange(of: isProcessing) { _, newValue in
            // Re-focus after streaming ends
            if !newValue {
                isFocused = true
            }
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
