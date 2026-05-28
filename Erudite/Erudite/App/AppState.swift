import Foundation
import Observation

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

    func initialize() async {
        do {
            let db = try DatabaseService()
            try db.setupSchema()
            try await WordLoader.seedDatabaseIfNeeded(database: db)
            self.databaseService = db
            self.wordLookupService = WordLookupService(database: db)

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

            // Wire turn completion: persist messages + trigger extraction
            runtime.onTurnComplete = { [weak sessions, weak memory, weak bgAI] userMsg, assistantMsg in
                guard let sessions, let memory else { return }
                // Persist messages
                try? sessions.saveMessage(userMsg)
                try? sessions.saveMessage(assistantMsg)
                try? sessions.updateSessionMeta()

                // Trigger extraction if enough turns
                let messageCount = runtime.messages.count
                if memory.shouldExtract(messageCount: messageCount) {
                    Task {
                        try? await memory.extractAndSave(
                            from: runtime.messages,
                            sessionId: sessions.currentSession?.id
                        )
                    }
                }

                // Auto-title after first exchange
                if sessions.currentSession?.title == "New Conversation" && messageCount >= 2 {
                    Task {
                        guard let bgAI else { return }
                        if let title = try? await bgAI.generateTitle(from: runtime.messages) {
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
        selectedTab = .flashcard
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case flashcard = "Flashcard"
    case typing = "Typing"
    case library = "Library"
    case dashboard = "Stats"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "house"
        case .flashcard: "book"
        case .typing: "keyboard"
        case .library: "books.vertical"
        case .dashboard: "chart.bar"
        }
    }
}
