import SwiftUI

// MARK: - Content View (Navigation Shell)

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showAIPanel: Bool = UserDefaults.standard.bool(forKey: "showAIPanel")
    @State private var aiPanelWidth: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "aiPanelWidth").clamped(to: 240...500, default: 300))
    @State private var chatFocusTrigger: Bool = false
    @State private var chatResignTrigger: Bool = false

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

            // AI Panel (right side) with draggable width
            if showAIPanel, let runtime = appState.aiRuntime {
                // Divider with drag handle overlay
                Divider()
                    .overlay {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .cursor(.resizeLeftRight)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        let newWidth = aiPanelWidth - value.translation.width
                                        aiPanelWidth = min(max(newWidth, 240), 500)
                                    }
                                    .onEnded { _ in
                                        UserDefaults.standard.set(Double(aiPanelWidth), forKey: "aiPanelWidth")
                                    }
                            )
                    }

                AIChatPanel(runtime: runtime, focusTrigger: $chatFocusTrigger, resignTrigger: $chatResignTrigger)
                    .frame(width: aiPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showAIPanel)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    // ⌘. three-state toggle:
                    // 1. Panel closed → open + focus input
                    // 2. Panel open, focus NOT in chat → focus input
                    // 3. Panel open, focus IN chat → close panel
                    if !showAIPanel {
                        showAIPanel = true
                        UserDefaults.standard.set(true, forKey: "showAIPanel")
                        chatFocusTrigger.toggle()
                    } else if appState.isChatInputActive {
                        // Already focused in chat → close panel
                        showAIPanel = false
                        UserDefaults.standard.set(false, forKey: "showAIPanel")
                    } else {
                        // Panel open but focus elsewhere → focus chat
                        chatFocusTrigger.toggle()
                    }
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

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
