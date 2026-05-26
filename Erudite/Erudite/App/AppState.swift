import Foundation
import Observation

@Observable
final class AppState {
    var selectedTab: SidebarTab = .today
    var isDBReady: Bool = false
    var wordCount: Int = 0
    var dueCount: Int = 0
    var newCount: Int = 0
    var studyMode: StudyQueueMode = .mixed

    // Multi-wordbook
    var wordBooks: [WordBook] = []
    var activeBookId: String? = nil  // nil = global (all books)

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
