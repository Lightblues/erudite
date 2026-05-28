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
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentSize)
    }
}
