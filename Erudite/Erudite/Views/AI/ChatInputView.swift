import SwiftUI

// MARK: - Chat Input View

/// Text input field with send/cancel button.
/// Shift+Enter for newline, Enter to send.
/// Always editable — even during streaming (user can prepare next message).
/// Focus is driven entirely by `appState.focusZone` / `appState.chatFocusNonce`.
struct ChatInputView: View {
    @Binding var text: String
    let isProcessing: Bool
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
                    // Esc: hand keyboard back to the main study area.
                    appState.focusMain()
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
            // Panel opened with chat focused → grab the input.
            if appState.focusZone == .chat { focusInput() }
        }
        .onChange(of: appState.chatFocusNonce) { _, _ in
            // Explicit focus request (⌘., clicking anywhere in the chat region,
            // session switch, popover dismiss). Force re-grab even if already focused.
            focusInput()
        }
        .onChange(of: appState.focusZone) { _, zone in
            if zone == .main {
                isFocused = false
            }
        }
        .onChange(of: isFocused) { _, focused in
            // If the input gains focus by any means, ensure the zone reflects it
            // so KeyCaptureView yields.
            if focused && appState.focusZone != .chat {
                appState.focusZone = .chat
            }
        }
    }

    /// Robustly move firstResponder to the input. Toggling false→true forces
    /// SwiftUI to re-assert focus even when `isFocused` is already true (e.g. focus
    /// was visually stolen by a selectable message) and survives the panel's
    /// entrance transition by retrying on the next runloop.
    private func focusInput() {
        isFocused = false
        DispatchQueue.main.async {
            isFocused = true
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
