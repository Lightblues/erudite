import SwiftUI
import AppKit

// MARK: - Focus Support
//
// Helpers that bridge AppKit window/geometry info into AppState so a window-level
// mouse monitor can route clicks to the correct focus zone (main vs chat).

/// Reports the chat panel's frame (in window base coordinates) to AppState.
/// Placed as a `.background` of the AI chat panel; resets to `.zero` when removed.
struct ChatRegionTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { RegionNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RegionNSView)?.report()
    }
}

private final class RegionNSView: NSView {
    // Never consume mouse events — purely a geometry probe.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        report()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    override func removeFromSuperview() {
        AppState.shared?.chatPanelFrame = .zero
        super.removeFromSuperview()
    }

    func report() {
        guard let window else {
            AppState.shared?.chatPanelFrame = .zero
            return
        }
        _ = window
        AppState.shared?.chatPanelFrame = convert(bounds, to: nil)
    }
}

/// Captures the hosting window so the global mouse monitor only reacts to the
/// main content window (and not, e.g., the Debug window).
struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            AppState.shared?.mainWindow = window
        }
    }
}

/// Holds the local mouse-down monitor token and removes it on teardown.
final class MouseMonitorHolder {
    var token: Any?

    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
            self.token = nil
        }
    }

    deinit { remove() }
}
