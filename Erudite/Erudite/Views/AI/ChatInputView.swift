import SwiftUI

// MARK: - Chat Input View

/// Text input field with send/cancel button.
/// Shift+Enter for newline, Enter to send.
/// Always editable — even during streaming (user can prepare next message).
/// Focus managed via `focusTrigger` (toggled by ⌘.) and `resignTrigger` (toggled by Esc).
struct ChatInputView: View {
    @Binding var text: String
    let isProcessing: Bool
    @Binding var focusTrigger: Bool
    @Binding var resignTrigger: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @Environment(AppState.self) private var appState
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
                        return .ignored  // Shift+Enter: newline
                    } else {
                        if canSend && !isProcessing {
                            onSend()
                        }
                        return .handled  // Enter: send (or no-op if empty/processing)
                    }
                }
                .onKeyPress(.escape, phases: .down) { _ in
                    // Esc: resign focus, return to main content
                    isFocused = false
                    return .handled
                }

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
        .padding(.vertical, 8)
        .onAppear {
            // Auto-focus when panel first opens
            isFocused = true
        }
        .onChange(of: focusTrigger) { _, _ in
            // Focus requested externally (⌘., session switch, tap on messages)
            isFocused = true
        }
        .onChange(of: resignTrigger) { _, _ in
            // Resign requested externally
            isFocused = false
        }
        .onChange(of: isFocused) { _, focused in
            // Report focus state so KeyCaptureView knows to yield
            appState.isChatInputActive = focused
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
