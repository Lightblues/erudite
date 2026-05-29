import SwiftUI

// MARK: - Content View (Navigation Shell)

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showAIPanel: Bool = UserDefaults.standard.bool(forKey: "showAIPanel")
    @State private var aiPanelWidth: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "aiPanelWidth").clamped(to: 240...500, default: 300))
    @State private var mouseMonitor = MouseMonitorHolder()

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

                AIChatPanel(runtime: runtime)
                    .frame(width: aiPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(MainWindowAccessor())
        .animation(.easeInOut(duration: 0.2), value: showAIPanel)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    toggleChat()
                } label: {
                    Image(systemName: showAIPanel ? "sidebar.right" : "sparkles")
                }
                .help("AI Companion: ⌘. focus chat · Esc back to study")
                .keyboardShortcut(".", modifiers: .command)
            }
        }
        .task {
            await appState.initialize()
        }
        .onAppear { installMouseMonitor() }
        .onDisappear { mouseMonitor.remove() }
    }

    /// ⌘. behavior:
    /// - panel hidden → show it and focus the chat input
    /// - panel shown, focus in main → move focus to chat
    /// - panel shown, focus already in chat → hide it and return to main
    private func toggleChat() {
        if showAIPanel {
            if appState.focusZone == .chat {
                showAIPanel = false
                UserDefaults.standard.set(false, forKey: "showAIPanel")
                appState.focusMain()
            } else {
                appState.focusChat()
            }
        } else {
            showAIPanel = true
            UserDefaults.standard.set(true, forKey: "showAIPanel")
            appState.focusChat()
        }
    }

    /// Window-level click router: clicking the chat region focuses the chat input,
    /// clicking anywhere else returns keyboard control to the main study area.
    /// This is what makes "click a region → keyboard goes there" deterministic.
    private func installMouseMonitor() {
        guard mouseMonitor.token == nil else { return }
        let state = appState
        mouseMonitor.token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window, window === state.mainWindow else { return event }
            // Ignore clicks in the title bar / toolbar so the ⌘. toggle button (which
            // reads `focusZone`) isn't pre-empted by this monitor.
            if event.locationInWindow.y > window.contentLayoutRect.maxY { return event }
            let frame = state.chatPanelFrame
            if frame != .zero && frame.contains(event.locationInWindow) {
                state.focusChat()
            } else {
                state.focusMain()
            }
            return event
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
