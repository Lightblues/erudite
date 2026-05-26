import SwiftUI
import AppKit

@main
struct EruditeApp: App {
    @State private var appState = AppState()

    init() {
        // Required for swift run: activate as foreground GUI app
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
    }
}
