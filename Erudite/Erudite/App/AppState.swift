import Foundation
import Observation
import AppKit

@Observable
final class AppState {
    /// Shared singleton for tool access (set by EruditeApp on launch)
    static var shared: AppState!

    var selectedTab: SidebarTab = .today
    var isDBReady: Bool = false
    var wordCount: Int = 0
    var dueCount: Int = 0
    var newCount: Int = 0
    var learnedCount: Int = 0  // cards that are no longer "new" in active book
    var studyMode: StudyQueueMode = .mixed

    // MARK: - Focus Model
    //
    // Single source of truth for "where does the keyboard go".
    // - `.main`: flashcard/typing keyboard control (KeyCaptureView grabs firstResponder)
    // - `.chat`: AI chat text input (TextEditor holds firstResponder)
    //
    // Both KeyCaptureView and ChatInputView derive their behavior from `focusZone`,
    // and a window-level mouse monitor updates it based on where the user clicks.
    enum FocusZone { case main, chat }

    /// Which region currently owns the keyboard.
    var focusZone: FocusZone = .main

    /// Bumped to (re)request chat-input focus, even when `focusZone` is already `.chat`
    /// (e.g. clicking on a selectable message should pull focus back to the input).
    var chatFocusNonce: Int = 0

    /// Number of word popovers currently visible. Bumped on appear, decremented on
    /// disappear by WordPopoverView/NotFoundPopoverView. KeyCaptureView checks this
    /// before consuming a key so flashcard/typing shortcuts (Esc, Space, ...) don't
    /// fire while a popover is on screen — the popover should own the keyboard.
    /// Not @Observable: bumped from view onAppear/onDisappear, no UI depends on it.
    @ObservationIgnored var popoverDepth: Int = 0

    func popoverDidAppear() { popoverDepth += 1 }
    func popoverDidDisappear() { popoverDepth = max(0, popoverDepth - 1) }

    /// A pending request to surface a word inside the Library tab. Consumed by
    /// LibraryView the next time it appears (or immediately if already on it).
    /// Set by AppState.openWordInLibrary; cleared by LibraryView after handling.
    var pendingLibraryWordId: String? = nil

    /// When non-nil, ContentView shows a modal sheet with the full WordDetailView
    /// for this word. Used by the popover's Cmd+O / "Show details" action so the
    /// user can deep-dive without leaving their current tab (Typing / Flashcard
    /// sessions stay alive).
    var detailSheetWordId: String? = nil

    /// Open the full WordDetailView in a modal sheet on top of the current tab.
    /// Preferred over openWordInLibrary because it doesn't disrupt study sessions.
    func showWordDetailSheet(_ wordId: String) {
        detailSheetWordId = wordId
    }

    /// Switch to the Library tab and request that `wordId` becomes the selected row.
    /// Used by the popover's Cmd+O / "Open in Library" action so users can jump from
    /// a popover view straight into the full WordDetail panel.
    func openWordInLibrary(_ wordId: String) {
        pendingLibraryWordId = wordId
        selectedTab = .library
    }

    /// The currently active KeyCaptureView NSView (registers itself when active).
    /// Not observed — purely an AppKit handle for direct focus control.
    @ObservationIgnored weak var activeKeyCapture: KeyNSView?

    /// Chat panel frame in window base coordinates (.zero when panel hidden).
    @ObservationIgnored var chatPanelFrame: CGRect = .zero

    /// The main content window (used to scope the global mouse monitor).
    @ObservationIgnored weak var mainWindow: NSWindow?

    /// Move keyboard focus to the AI chat input (opening behavior handled by caller).
    func focusChat() {
        focusZone = .chat
        chatFocusNonce &+= 1
    }

    /// Move keyboard focus back to the main study area and re-grab firstResponder.
    func focusMain() {
        focusZone = .main
        activeKeyCapture?.grabFocus()
    }

    // Multi-wordbook
    var wordBooks: [WordBook] = []
    var activeBookId: String? = UserDefaults.standard.string(forKey: "activeBookId") {
        didSet {
            if let id = activeBookId {
                UserDefaults.standard.set(id, forKey: "activeBookId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeBookId")
            }
        }
    }

    var activeBook: WordBook? {
        wordBooks.first { $0.id == activeBookId }
    }

    private(set) var databaseService: DatabaseService?
    private(set) var wordLookupService: WordLookupService?
    private(set) var aiRuntime: AgentRuntime?
    private(set) var sessionManager: SessionManager?
    private(set) var memoryStore: MemoryStore?
    private(set) var backgroundAI: BackgroundAI?

    /// Persistent UI state for the Library tab. Lives at the AppState
    /// level so switching tabs doesn't reset the loaded page, selection,
    /// filter pickers, or split-pane width. See LibraryState.
    let libraryState = LibraryState()

    /// Process-wide settings (unitSize, etc.). One source of truth shared
    /// by Flashcard chunk size, Book Chapter size, and Today's review
    /// slicer — see AppSettings.
    let settings = AppSettings()

    func initialize() async {
        do {
            let db = try DatabaseService()
            try db.setupSchema()
            try await WordLoader.seedDatabaseIfNeeded(database: db)
            self.databaseService = db
            self.wordLookupService = WordLookupService(database: db)
            AITracer.shared.configure(db: db)
            Log.app.info("Database initialized")

            // AI subsystem
            let client = AnthropicClient()
            let runtime = AgentRuntime(client: client, db: db)
            let bgAI = BackgroundAI(client: client)
            let memory = MemoryStore(db: db, backgroundAI: bgAI)
            let sessions = SessionManager(db: db)

            // Load last session's messages into runtime
            let restoredMessages = try sessions.loadOrCreateLastSession()
            if !restoredMessages.isEmpty {
                runtime.loadMessages(restoredMessages)
            }
            sessions.refreshSessionList()

            // Wire turn completion: persist ALL messages + trigger extraction
            runtime.onTurnComplete = { [weak sessions, weak memory, weak bgAI] allMessages in
                guard let sessions, let memory else { return }
                // Persist all messages (saveMessage uses INSERT OR REPLACE, so re-saving is safe)
                for msg in allMessages {
                    try? sessions.saveMessage(msg)
                }
                try? sessions.updateSessionMeta()

                // Trigger extraction if enough turns
                let messageCount = allMessages.count
                if memory.shouldExtract(messageCount: messageCount) {
                    Task {
                        try? await memory.extractAndSave(
                            from: allMessages,
                            sessionId: sessions.currentSession?.id
                        )
                    }
                }

                // Auto-title after first exchange
                if sessions.currentSession?.title == "New Conversation" && messageCount >= 2 {
                    Task {
                        guard let bgAI else { return }
                        if let title = try? await bgAI.generateTitle(from: allMessages) {
                            sessions.updateTitle(title)
                        }
                    }
                }
            }

            self.aiRuntime = runtime
            self.backgroundAI = bgAI
            self.memoryStore = memory
            self.sessionManager = sessions

            self.wordCount = try db.fetchAllWords().count
            self.wordBooks = try db.fetchWordBooks()
            // Validate persisted bookId still exists
            if let savedId = activeBookId, !wordBooks.contains(where: { $0.id == savedId }) {
                activeBookId = nil
            }
            self.isDBReady = true
            refreshStats()
        } catch {
            print("Failed to initialize database: \(error)")
        }
    }

    /// Flush memory extraction (call on app going to background)
    func flushMemory() {
        guard let memoryStore, let aiRuntime, let sessionManager else { return }
        Task {
            await memoryStore.flushExtraction(
                from: aiRuntime.messages,
                sessionId: sessionManager.currentSession?.id
            )
        }
    }

    func refreshStats() {
        guard let db = databaseService else { return }
        do {
            dueCount = try db.fetchDueCount(inBook: activeBookId)
            newCount = try db.fetchNewCount(inBook: activeBookId)
            learnedCount = try db.fetchLearnedCount(inBook: activeBookId)
        } catch {
            print("Failed to refresh stats: \(error)")
        }
    }

    func selectBook(_ bookId: String?) {
        activeBookId = bookId
        refreshStats()
    }

    func startStudy(mode: StudyQueueMode = .mixed) {
        studyMode = mode
        currentUnit = nil   // legacy entry — clears any pinned unit
        selectedTab = .flashcard
    }

    // MARK: - Unit-driven study flow
    //
    // The user picks a StudyUnit on Today, optionally previews it, then
    // launches into either Flashcard or Typing. The chosen unit is pinned
    // to AppState.currentUnit so the receiving view consumes the same
    // resolved cards (no re-querying SQL inside the view model). On
    // session completion, currentUnit is cleared.

    /// The unit the user has committed to studying. Nil = no active
    /// unit-driven session (StudyView/TypingView fall back to their
    /// legacy queue-loading behavior).
    var currentUnit: StudyUnit?

    /// Set the active unit and switch to the chosen study mode tab.
    /// Used by UnitPreviewView's [Start with Flashcard] / [Start with Typing].
    func startUnit(_ unit: StudyUnit, in mode: UnitStudyMode) {
        currentUnit = unit
        switch mode {
        case .flashcard: selectedTab = .flashcard
        case .typing:    selectedTab = .typing
        }
    }
}

enum UnitStudyMode {
    case flashcard
    case typing
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case flashcard = "Flashcard"
    case typing = "Typing"
    case library = "Library"
    case dashboard = "Stats"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "house"
        case .plan: "calendar.day.timeline.left"
        case .flashcard: "book"
        case .typing: "keyboard"
        case .library: "books.vertical"
        case .dashboard: "chart.bar"
        }
    }
}
