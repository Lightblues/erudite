import Foundation

// MARK: - LibraryState
//
// Process-wide @Observable state for the Library tab. Promoted out of the
// LibraryView itself so that switching tabs (Today → Library → Today) does
// NOT clobber:
//
// - the loaded summaries set
// - selected word id (split layout)
// - filter / sort / search picker positions
// - the selected unit index (when browsing within a unit)
// - the resizable list-pane width
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
    /// Index of the active book unit, or nil for "All units" (= entire
    /// book). When non-nil:
    /// - the SQL slice is the corresponding unit's word range
    /// - State / Sort pickers are hidden in the header (the unit IS the
    ///   filter; sort is forced to .bookOrder so the unit's natural
    ///   order is preserved)
    /// - the footer shows progress counts + [Flashcard] [Typing] direct-
    ///   start buttons that consume the unit
    var selectedUnitIndex: Int?
    /// Cached unit ranges for the active book. Populated when the user
    /// picks a book (or unitSize changes); empty when no book selected.
    /// Drives both the picker labels and the wordId slice when a unit
    /// is active.
    var unitRanges: [DatabaseService.UnitRange] = []

    // MARK: - Loaded data

    var summaries: [WordSummary] = []
    var totalMatching: Int = 0
    var isLoading: Bool = false
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
        selectedUnitIndex = nil
        unitRanges = []
        summaries = []
        totalMatching = 0
        isLoading = false
        didInitFromAppState = false
        selectedWordId = nil
        selectedFullWord = nil
    }
}
