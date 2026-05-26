import SwiftUI

// MARK: - Content View (Navigation Shell)

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

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
