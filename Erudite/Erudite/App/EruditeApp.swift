import SwiftUI

@main
struct EruditeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentSize)
    }
}
