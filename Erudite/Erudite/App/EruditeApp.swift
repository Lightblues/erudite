import SwiftUI

@main
struct EruditeApp: App {
    @State private var appState: AppState

    init() {
        let state = AppState()
        AppState.shared = state
        self._appState = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 800, minHeight: 500)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                    appState.flushMemory()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentSize)

        // Debug panel window (⌘⇧D from menu)
        Window("Debug", id: "debug") {
            DebugPanelView()
                .frame(minWidth: 700, minHeight: 400)
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .defaultSize(width: 800, height: 500)
    }
}
