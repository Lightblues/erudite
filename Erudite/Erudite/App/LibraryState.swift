import Foundation

// MARK: - LibraryState
//
// Process-wide @Observable state for the Library tab. Promoted out of the
// LibraryView itself so that switching tabs (Today → Library → Today) does
// NOT clobber:
//
// - the loaded summaries page
// - selected word id (split layout)
// - filter / sort / search picker positions
// - the resizable list-pane width
// - the loaded offset (so "Load More" sticks across tab switches)
//
// SwiftUI rebuilds the LibraryView when the user switches tabs, which
// re-runs `.task` and resets every `@State` to its initial value. By living
// here, those values survive.
//
// Construction is owned by AppState (single instance). Views observe it
// via Environment(AppState.self). Persistence: only the split-pane width
// is written to UserDefaults — everything else is in-memory because it's
// derived from filter pickers that the user can change anyway.

@MainActor
@Observable
final class LibraryState {

    // MARK: - Filters (live state of the pickers)

    /// nil = "All Books". Mirrors AppState.activeBookId on first appear and
    /// is two-way synced after that.
    var selectedBookId: String?
    var selectedState: WordStateFilter = .all
    var selectedSort: WordSort = .bookOrder
    var searchText: String = ""
    var debouncedSearch: String = ""
    /// Words list (default) vs Chapters list (when a Book is picked). The
    /// Chapters mode sliced the book's words into `unitSize` chapters and
    /// lets the user pick one to study via the same UnitPreview pipeline.
    var viewMode: LibraryViewMode = .words

    // MARK: - Loaded data

    var summaries: [WordSummary] = []
    var totalMatching: Int = 0
    var totalAll: Int = 0
    var isLoading: Bool = false
    var loadedCount: Int = 0
    var didInitFromAppState: Bool = false   // gate for "first appear" wiring

    // MARK: - Selection (split layout)

    var selectedWordId: String?
    var selectedFullWord: Word?

    /// Lowercased starting letters that have at least one row under the
    /// current filters. Drives the A-Z jump bar's dim/active state.
    var availableLetters: Set<String> = []

    // MARK: - UI: split widths

    /// Width of the LIST pane in the split layout (Mail-style: list narrow,
    /// detail wide). Default 360pt; user can drag 280–600pt. Persisted to
    /// UserDefaults so it survives app restarts.
    var listPaneWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(listPaneWidth), forKey: Self.widthKey)
        }
    }
    static let widthKey = "library.listPaneWidth"
    static let widthMin: CGFloat = 280
    static let widthMax: CGFloat = 600
    static let widthDefault: CGFloat = 360

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.widthKey)
        let initial = stored == 0 ? Self.widthDefault : CGFloat(stored)
        self.listPaneWidth = min(max(initial, Self.widthMin), Self.widthMax)
    }

    // MARK: - Reset (used when the database is wiped or for tests)

    func reset() {
        selectedBookId = nil
        selectedState = .all
        selectedSort = .bookOrder
        searchText = ""
        debouncedSearch = ""
        viewMode = .words
        summaries = []
        totalMatching = 0
        totalAll = 0
        isLoading = false
        loadedCount = 0
        didInitFromAppState = false
        selectedWordId = nil
        selectedFullWord = nil
    }
}

/// Library top-level mode: word list (default) vs chapter list.
nonisolated enum LibraryViewMode: String, CaseIterable, Hashable {
    case words
    case chapters

    var label: String {
        switch self {
        case .words: "Words"
        case .chapters: "Chapters"
        }
    }
}
