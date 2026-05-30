import SwiftUI
import AppKit

// MARK: - Key Capture View

/// A transparent NSView-based keyboard interceptor for reliable key handling.
/// Unlike SwiftUI's @FocusState + .onKeyPress, this approach:
/// - Always accepts first responder
/// - Re-grabs focus when stolen (by popovers, buttons, etc.)
/// - Handles key events deterministically without timers
struct KeyCaptureView: NSViewRepresentable {
    /// Return true if the key event was handled
    let onKeyDown: (KeyEvent) -> Bool

    /// Whether this view should actively maintain focus
    var isActive: Bool = true

    func makeNSView(context: Context) -> KeyNSView {
        let view = KeyNSView()
        view.onKeyDown = onKeyDown
        view.isActiveCapture = isActive
        return view
    }

    func updateNSView(_ nsView: KeyNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.isActiveCapture = isActive
        if isActive {
            // Ensure we have focus when becoming active. Guard at fire-time:
            // the zone may have flipped to .chat before this runs.
            DispatchQueue.main.async {
                guard nsView.isActiveCapture else { return }
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

// MARK: - Key Event (simplified for SwiftUI consumption)

struct KeyEvent {
    let keyCode: UInt16
    let characters: String
    let modifiers: NSEvent.ModifierFlags

    var isSpace: Bool { keyCode == 49 }
    var isReturn: Bool { keyCode == 36 }
    var isEscape: Bool { keyCode == 53 }
    var isTab: Bool { keyCode == 48 }
    var isLeftArrow: Bool { keyCode == 123 }
    var isRightArrow: Bool { keyCode == 124 }

    /// The character typed (lowercased, no modifiers)
    var char: Character? {
        let chars = characters.lowercased()
        guard chars.count == 1 else { return nil }
        return chars.first
    }

    var hasCommand: Bool { modifiers.contains(.command) }
    var hasShift: Bool { modifiers.contains(.shift) }
}

// MARK: - NSView Implementation

final class KeyNSView: NSView {
    var onKeyDown: (KeyEvent) -> Bool = { _ in false }
    var isActiveCapture: Bool = true {
        didSet { updateRegistration() }
    }

    override var acceptsFirstResponder: Bool { true }

    // CRITICAL: Pass all mouse events through to SwiftUI views underneath
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Forcibly take firstResponder (called by AppState.focusMain on main-area clicks).
    func grabFocus() {
        guard isActiveCapture, let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActiveCapture else { return }
            window.makeFirstResponder(self)
        }
    }

    /// Register/unregister as the app's active key capture view so AppState can
    /// restore focus to it directly when the user clicks back into the main area.
    private func updateRegistration() {
        if isActiveCapture, window != nil {
            AppState.shared?.activeKeyCapture = self
        } else if AppState.shared?.activeKeyCapture === self {
            AppState.shared?.activeKeyCapture = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        let keyEvent = KeyEvent(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers ?? "",
            modifiers: event.modifierFlags
        )
        if !onKeyDown(keyEvent) {
            // Not handled — don't call super to avoid system beep
            // super.keyDown(with: event) would trigger the bonk sound
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRegistration()
        if isActiveCapture {
            window?.makeFirstResponder(self)
        }
        // Listen for window becoming key (after popover dismiss, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    override func removeFromSuperview() {
        NotificationCenter.default.removeObserver(self)
        if AppState.shared?.activeKeyCapture === self {
            AppState.shared?.activeKeyCapture = nil
        }
        super.removeFromSuperview()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard isActiveCapture,
              let window = self.window,
              notification.object as? NSWindow == window else { return }
        // Re-grab focus after popover dismiss or window switch — but not while
        // a popover is currently up (let it own the keyboard).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActiveCapture else { return }
            if (AppState.shared?.popoverDepth ?? 0) > 0 { return }
            window.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        guard isActiveCapture else { return result }

        // While a word popover is visible, let it own firstResponder so its
        // keyboardShortcut(.escape) etc. work. Re-grab once the popover closes.
        if (AppState.shared?.popoverDepth ?? 0) > 0 {
            return result
        }

        // Re-grab focus after a runloop cycle, unless a text field needs it
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActiveCapture,
                  let window = self.window else { return }
            // Don't steal from text input views (e.g., search fields)
            if let current = window.firstResponder, current is NSTextView {
                return
            }
            // Also don't steal while a popover is up (depth may have flipped
            // between the original resign and this async tick).
            if (AppState.shared?.popoverDepth ?? 0) > 0 {
                return
            }
            window.makeFirstResponder(self)
        }
        return result
    }

    // Prevent system beep for unhandled keys
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let Cmd+shortcuts pass through to the system
        if event.modifierFlags.contains(.command) {
            return super.performKeyEquivalent(with: event)
        }
        return false
    }
}
