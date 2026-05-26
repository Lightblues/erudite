import Foundation
import Observation

@Observable
final class AppState {
    var selectedTab: SidebarTab = .today
    var isDBReady: Bool = false
    var wordCount: Int = 0

    private(set) var databaseService: DatabaseService?

    func initialize() async {
        do {
            let db = try DatabaseService()
            try db.setupSchema()
            try await WordLoader.seedDatabaseIfNeeded(database: db)
            self.databaseService = db
            self.wordCount = try db.fetchAllWords().count
            self.isDBReady = true
        } catch {
            print("Failed to initialize database: \(error)")
        }
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
