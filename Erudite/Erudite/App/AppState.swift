import Foundation
import Observation

@Observable
final class AppState {
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

    func initialize() async {
        do {
            let db = try DatabaseService()
            try db.setupSchema()
            try await WordLoader.seedDatabaseIfNeeded(database: db)
            self.databaseService = db
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
        selectedTab = .study
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case study = "Learn"
    case library = "Library"
    case dashboard = "Stats"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "house"
        case .study: "book"
        case .library: "books.vertical"
        case .dashboard: "chart.bar"
        }
    }
}
