import SwiftUI

// MARK: - Content View (Navigation Shell)

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showAIPanel: Bool = UserDefaults.standard.bool(forKey: "showAIPanel")

    var body: some View {
        @Bindable var state = appState

        HStack(spacing: 0) {
            // Main app content
            NavigationSplitView {
                List(SidebarTab.allCases, selection: $state.selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            } detail: {
                detailView(for: appState.selectedTab)
            }
            .frame(maxWidth: .infinity)

            // AI Panel (right side)
            if showAIPanel, let runtime = appState.aiRuntime {
                Divider()
                AIChatPanel(runtime: runtime)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showAIPanel)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showAIPanel.toggle()
                    UserDefaults.standard.set(showAIPanel, forKey: "showAIPanel")
                } label: {
                    Image(systemName: showAIPanel ? "sidebar.right" : "sparkles")
                }
                .help("Toggle AI Companion (⌘.)")
                .keyboardShortcut(".", modifiers: .command)
            }
        }
        .task {
            await appState.initialize()
        }
    }

    @ViewBuilder
    private func detailView(for tab: SidebarTab) -> some View {
        switch tab {
        case .today:
            TodayView()
        case .flashcard:
            StudyView()
        case .typing:
            TypingView()
        case .library:
            LibraryView()
        case .dashboard:
            DashboardView()
        }
    }
}
