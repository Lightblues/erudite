import SwiftUI

// MARK: - Library View
//
// Library answers one question: "browse this app's words." Everything else
// is a slice on that list.
//
//   - Book picker        : which book (or "All Books")
//   - Unit picker        : which slice within the book (or "All units")
//                          Visible only when a Book is selected.
//   - State picker       : All / New / Learning / Review / Mature
//                          Hidden in Unit mode — the unit is small enough
//                          that the per-row state badge is sufficient.
//   - Sort picker        : Book Order / A → Z
//                          Hidden in Unit mode — units are book-order slices,
//                          re-sorting them alphabetically would scatter them.
//   - Search             : text search; cross-cuts everything
//   - A-Z jump bar       : Visible only when sort = .alphabetical
//
// In Unit mode the footer surfaces:
//   - progress counts (mastered / review / learning / new)
//   - direct-start [Flashcard] [Typing] action buttons that build the
//     unit and pin it to AppState.currentUnit, no UnitPreview detour
//
// State storage:
//   - All "live state" (loaded summaries, selection, filter pickers, list
//     pane width) lives in AppState.libraryState so switching tabs doesn't
//     reset the user's place. See LibraryState.
//
// Pagination was removed in erudite-31 — Library now reads the full
// matching slice and lets SwiftUI List recycle rows lazily. Pagination
// + jump-bar were two overlapping "position" mental models.

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    // Search-debounce task. Local because it's only meaningful in-flight;
    // we don't want to pin a Task across tab switches.
    @State private var searchDebounceTask: Task<Void, Never>?

    // Layout breakpoint for split vs narrow modes.
    private let splitMinWidth: CGFloat = 900

    private var lib: LibraryState { appState.libraryState }

    /// True iff the user has selected a specific unit. Drives header
    /// picker visibility and footer mode.
    private var inUnitMode: Bool { lib.selectedUnitIndex != nil }

    /// The currently-selected UnitRange, if any.
    private var selectedUnit: DatabaseService.UnitRange? {
        guard let idx = lib.selectedUnitIndex else { return nil }
        return lib.unitRanges.first(where: { $0.index == idx })
    }

    var body: some View {
        @Bindable var lib = appState.libraryState

        GeometryReader { geo in
            let isSplit = geo.size.width >= splitMinWidth
            Group {
                if isSplit {
                    splitLayout(totalWidth: geo.size.width)
                } else {
                    narrowLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $lib.searchText, prompt: "Search spelling or definition...")
        .onChange(of: lib.searchText) { _, newValue in
            scheduleSearch(newValue)
        }
        .onChange(of: lib.selectedBookId) { _, newValue in
            // Two-way sync: keep AppState in sync so Today / Plan see the same
            // book. Skip the initial sync triggered by .task seeding.
            if lib.didInitFromAppState && newValue != appState.activeBookId {
                appState.selectBook(newValue)
            }
            // Book changed → unit list is now stale, and any selected unit
            // index is meaningless in the new book.
            lib.selectedUnitIndex = nil
            Task {
                await reloadUnitRanges()
                await reload()
            }
        }
        .onChange(of: lib.selectedState) { _, _ in Task { await reload() } }
        .onChange(of: lib.selectedSort) { _, _ in Task { await reload() } }
        .onChange(of: lib.selectedUnitIndex) { _, _ in Task { await reload() } }
        .onChange(of: lib.selectedWordId) { _, newId in
            Task { await loadFullWord(for: newId) }
        }
        .onChange(of: appState.settings.unitSize) { _, _ in
            Task { await reloadUnitRanges() }
        }
        .onChange(of: appState.activeBookId) { _, newValue in
            // Pull AppState changes (e.g. user changed book on Today) into our
            // local state so the picker reflects it.
            if newValue != lib.selectedBookId {
                lib.selectedBookId = newValue
            }
        }
        .task {
            // Seed once. After the first appear, this view may rebuild on tab
            // switches but LibraryState persists, so we keep the user's place.
            if !lib.didInitFromAppState {
                lib.selectedBookId = appState.activeBookId
                lib.didInitFromAppState = true
                await reloadUnitRanges()
                await reload()
            } else if lib.summaries.isEmpty {
                // Came back to a state that was emptied — refetch.
                await reloadUnitRanges()
                await reload()
            }
        }
    }

    // MARK: - Layouts

    /// Split layout with a draggable vertical divider between list and detail.
    @ViewBuilder
    private func splitLayout(totalWidth: CGFloat) -> some View {
        @Bindable var lib = appState.libraryState
        let listWidth = clampListWidth(lib.listPaneWidth, total: totalWidth)

        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                listPane
                    .frame(width: listWidth)
                if lib.selectedSort == .alphabetical {
                    AlphabetJumpBar(onJump: jumpToLetter)
                }
                ResizableDivider(width: $lib.listPaneWidth, totalWidth: totalWidth)
                detailPane
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Keep the persisted list width inside the allowed range AND inside what
    /// the current window actually has room for (so a saved 600pt doesn't
    /// completely cover the detail pane after the user shrinks the window).
    private func clampListWidth(_ value: CGFloat, total: CGFloat) -> CGFloat {
        let hardMin = LibraryState.widthMin
        let hardMax = LibraryState.widthMax
        // Reserve at least 360pt for the detail pane.
        let softMax = max(hardMin, total - 360)
        return min(max(value, hardMin), min(hardMax, softMax))
    }

    private var narrowLayout: some View {
        // Wrap in NavigationStack so .navigationDestination(for:) resolves
        // (NavigationSplitView's detail column doesn't supply its own stack).
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                narrowContent
            }
            .navigationDestination(for: String.self) { wordId in
                WordDetailLoader(wordId: wordId)
            }
        }
    }

    // MARK: - Header
    //
    // Two rows. First row: title + loading indicator. Second row: the
    // pickers, in priority order. Unit picker is the new center of gravity
    // when a book is selected — it sits right next to Book to make the
    // "book → unit" relationship visually obvious.

    private var header: some View {
        @Bindable var lib = appState.libraryState
        return VStack(spacing: 8) {
            HStack {
                Text("Word Library")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                if lib.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                if !appState.wordBooks.isEmpty {
                    Picker("Book", selection: $lib.selectedBookId) {
                        Text("All Books").tag(String?.none)
                        ForEach(appState.wordBooks) { book in
                            Text(book.name).tag(String?.some(book.id))
                        }
                    }
                    .frame(maxWidth: 220)
                }

                // Unit picker only meaningful when a book is selected.
                if lib.selectedBookId != nil, !lib.unitRanges.isEmpty {
                    Picker("Unit", selection: $lib.selectedUnitIndex) {
                        Text("All units").tag(Int?.none)
                        Divider()
                        ForEach(lib.unitRanges) { range in
                            Text("\(range.label) (\(range.rangeText))")
                                .tag(Int?.some(range.index))
                        }
                    }
                    .frame(maxWidth: 280)
                }

                // State + Sort hide in Unit mode — they'd be redundant
                // (per-row state badges are visible anyway, and sorting
                // alphabetically would scatter the unit's natural order).
                if !inUnitMode {
                    Picker("State", selection: $lib.selectedState) {
                        ForEach(WordStateFilter.allCases, id: \.self) { state in
                            Text(state.label).tag(state)
                        }
                    }
                    .frame(maxWidth: 140)

                    Picker("Sort", selection: $lib.selectedSort) {
                        ForEach(WordSort.allCases, id: \.self) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                    .frame(maxWidth: 160)
                }

                Spacer()
            }
        }
        .padding()
    }

    // MARK: - List pane (used in both layouts)

    @ViewBuilder
    private var listPane: some View {
        @Bindable var lib = appState.libraryState
        if !appState.isDBReady {
            ProgressView("Loading database...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lib.summaries.isEmpty && !lib.debouncedSearch.isEmpty {
            ContentUnavailableView.search(text: lib.debouncedSearch)
        } else if lib.summaries.isEmpty {
            ContentUnavailableView(
                "No words match these filters",
                systemImage: "tray",
                description: Text(emptyDescriptionText)
            )
        } else {
            VStack(spacing: 0) {
                // Selection binding makes Up/Down move selection automatically.
                List(lib.summaries, selection: $lib.selectedWordId) { summary in
                    WordSummaryRow(summary: summary, trailingForSort: lib.selectedSort)
                        .tag(summary.id)
                }
                .listStyle(.inset)
                .onKeyPress(.escape) {
                    if lib.selectedWordId != nil {
                        lib.selectedWordId = nil
                        return .handled
                    }
                    return .ignored
                }

                footer
            }
        }
    }

    private var emptyDescriptionText: String {
        if inUnitMode {
            return "This unit appears empty. Try clearing the search."
        }
        return "Try clearing the State picker or selecting a different book."
    }

    // MARK: - Footer
    //
    // Two flavors:
    //
    // - In Unit mode, the footer becomes an action surface: progress
    //   counts on the left, [Flashcard] [Typing] direct-start buttons on
    //   the right. The user already saw the words in the list above —
    //   no UnitPreview detour, just press a button and study.
    //
    // - In Book mode, the footer is a thin status line showing how many
    //   rows match the current filters.

    @ViewBuilder
    private var footer: some View {
        if inUnitMode {
            unitFooter
        } else {
            bookFooter
        }
    }

    private var bookFooter: some View {
        HStack(spacing: 12) {
            Text(bookFooterText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var bookFooterText: String {
        if lib.totalMatching == 0 { return "No matches" }
        return "Showing \(lib.summaries.count)"
    }

    @ViewBuilder
    private var unitFooter: some View {
        let counts = unitCounts
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let unit = selectedUnit {
                    Text(unit.rangeText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    startUnit(in: .flashcard)
                } label: {
                    Label("Flashcard", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
                .disabled(lib.summaries.isEmpty)

                Button {
                    startUnit(in: .typing)
                } label: {
                    Label("Typing", systemImage: "keyboard")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)
                .disabled(lib.summaries.isEmpty)
            }
            HStack(spacing: 14) {
                progressChip(label: "Mastered", count: counts.mastered, color: .green)
                progressChip(label: "Review", count: counts.review, color: .orange)
                progressChip(label: "Learning", count: counts.learning, color: .yellow)
                progressChip(label: "New", count: counts.new, color: .blue)
                Spacer()
                Text("\(lib.summaries.count) words")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func progressChip(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(count > 0 ? color : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? .primary : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Per-state count derived from the loaded summaries. Mature is
    /// approximated as `.review` (we don't have stability in the
    /// projection); good enough as a coarse "I've got this" signal.
    private var unitCounts: (mastered: Int, review: Int, learning: Int, new: Int) {
        var mastered = 0, review = 0, learning = 0, new = 0
        for s in lib.summaries {
            switch s.cardState {
            case .review: review += 1; mastered += 1
            case .learning, .relearning: learning += 1
            case .new, .none: new += 1
            }
        }
        // mastered double-counts review for now (review = "I'm in the
        // review schedule, doing OK"). Strict mature would need
        // stability >= 21d which lives on reviewCard, not the summary.
        return (mastered, review, learning, new)
    }

    private func startUnit(in mode: UnitStudyMode) {
        guard let bookId = lib.selectedBookId,
              let idx = lib.selectedUnitIndex,
              let db = appState.databaseService else { return }
        let chapterSize = appState.settings.unitSize
        let builder = StudyQueueBuilder(db: db)
        guard let unit = try? builder.buildChapterUnit(
            bookId: bookId,
            chapterIndex: idx,
            chapterSize: chapterSize
        ) else { return }
        appState.startUnit(unit, in: mode)
    }

    // MARK: - Detail pane (split layout only)

    @ViewBuilder
    private var detailPane: some View {
        if let word = lib.selectedFullWord {
            WordDetailView(word: word, escapeBehavior: .embedded)
        } else if lib.selectedWordId != nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Select a word",
                systemImage: "sidebar.right",
                description: Text("Use ↑ and ↓ to browse. Esc clears selection.")
            )
        }
    }

    // MARK: - Narrow layout content (push navigation)

    @ViewBuilder
    private var narrowContent: some View {
        if !appState.isDBReady {
            ProgressView("Loading database...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lib.summaries.isEmpty && !lib.debouncedSearch.isEmpty {
            ContentUnavailableView.search(text: lib.debouncedSearch)
        } else if lib.summaries.isEmpty {
            ContentUnavailableView(
                "No words match these filters",
                systemImage: "tray",
                description: Text(emptyDescriptionText)
            )
        } else {
            VStack(spacing: 0) {
                List(lib.summaries) { summary in
                    NavigationLink(value: summary.id) {
                        WordSummaryRow(summary: summary, trailingForSort: lib.selectedSort)
                    }
                }
                .listStyle(.inset)

                footer
            }
        }
    }

    // MARK: - Loading

    /// Debounce search so 8 keystrokes don't fire 8 SQL queries.
    private func scheduleSearch(_ value: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await MainActor.run { appState.libraryState.debouncedSearch = value }
            await reload()
        }
    }

    /// Refresh the cached unit ranges for the active book. Cheap (one
    /// SELECT, ~13K rows × one column) and only fires on book change /
    /// unitSize change / first appear.
    private func reloadUnitRanges() async {
        guard let db = appState.databaseService,
              let bookId = lib.selectedBookId else {
            lib.unitRanges = []
            return
        }
        let size = appState.settings.unitSize
        lib.unitRanges = (try? db.fetchUnitRanges(bookId: bookId, unitSize: size)) ?? []
        // If the user had selected a unit that no longer exists (book
        // changed, unitSize shrunk), clear it.
        if let idx = lib.selectedUnitIndex,
           !lib.unitRanges.contains(where: { $0.index == idx }) {
            lib.selectedUnitIndex = nil
        }
    }

    private func reload() async {
        guard let db = appState.databaseService else { return }
        lib.isLoading = true
        defer { lib.isLoading = false }

        let search = lib.debouncedSearch.isEmpty ? nil : lib.debouncedSearch
        do {
            // Effective filters depend on whether we're in Unit mode.
            // In Unit mode the State picker is hidden, so we always
            // query .all (the unit IS the slice).
            let effectiveState: WordStateFilter = inUnitMode ? .all : lib.selectedState
            // Sort is forced to .bookOrder in Unit mode for the same
            // reason the picker hides.
            let effectiveSort: WordSort = inUnitMode ? .bookOrder : lib.selectedSort

            // No limit — read full matching set, SwiftUI List recycles.
            var page = try db.fetchWordSummaries(
                book: lib.selectedBookId,
                state: effectiveState,
                search: search,
                sort: effectiveSort,
                limit: nil,
                offset: 0
            )

            // In Unit mode, slice the loaded set to the unit's range.
            // We could push the slice into SQL via OFFSET/LIMIT on the
            // book-ordered query, but the search/state-filter
            // interaction would make that fragile — and the full set is
            // already in memory. Slicing in Swift keeps the SQL clean.
            if inUnitMode, let unit = selectedUnit {
                page = sliceForUnit(page, unit: unit)
            }

            let count = page.count
            // Refresh the jump-bar's "available letters" set — used to dim
            // letters with zero matches under the current filters.
            let letters = (try? db.availableStartingLetters(
                book: lib.selectedBookId,
                state: effectiveState,
                search: search
            )) ?? []
            lib.totalMatching = count
            lib.summaries = page
            lib.availableLetters = letters

            // Drop selection if the selected word is no longer in the page.
            if let id = lib.selectedWordId, !page.contains(where: { $0.id == id }) {
                lib.selectedWordId = nil
            }
        } catch {
            print("Library reload failed: \(error)")
            lib.summaries = []
            lib.totalMatching = 0
            lib.availableLetters = []
        }
    }

    /// Slice a book-ordered summary list down to the given unit's range.
    /// We look up the unit's `firstSpelling` in the page (book-ordered,
    /// possibly state/search-filtered) and take a contiguous window
    /// from there. If `lastSpelling` falls within `count` rows we end
    /// there; otherwise we truncate at `firstIdx + count`. Search/State
    /// filtering can shrink the slice — that's the desired behavior:
    /// "Unit 5 + State New" = "new words within Unit 5's range."
    private func sliceForUnit(_ page: [WordSummary], unit: DatabaseService.UnitRange) -> [WordSummary] {
        guard let firstIdx = page.firstIndex(where: { $0.spelling == unit.firstSpelling }) else {
            return []
        }
        let endCap = min(firstIdx + unit.count, page.count)
        if let lastIdxInWindow = page[firstIdx..<endCap].firstIndex(where: { $0.spelling == unit.lastSpelling }) {
            return Array(page[firstIdx...lastIdxInWindow])
        }
        return Array(page[firstIdx..<endCap])
    }

    /// Jump to the first row whose spelling starts with `letter`.
    /// Only meaningful under .alphabetical sort (the bar only shows
    /// then). We scroll to the row by setting selection — SwiftUI List
    /// auto-scrolls to keep the selection visible.
    private func jumpToLetter(_ letter: Character) {
        guard lib.selectedSort == .alphabetical else { return }
        let key = String(letter).lowercased()
        if let target = lib.summaries.first(where: { $0.spelling.lowercased().hasPrefix(key) }) {
            lib.selectedWordId = target.id
        }
    }

    /// Fetch the full Word for the right-hand detail panel (split layout).
    private func loadFullWord(for wordId: String?) async {
        guard let wordId, let db = appState.databaseService else {
            lib.selectedFullWord = nil
            return
        }
        // Avoid an in-flight flicker if the selection didn't actually change.
        if lib.selectedFullWord?.id == wordId { return }
        do {
            lib.selectedFullWord = try db.fetchWord(id: wordId)
        } catch {
            print("Library loadFullWord failed: \(error)")
            lib.selectedFullWord = nil
        }
    }
}

// MARK: - AlphabetJumpBar
//
// Vertical strip of A-Z letters between the list pane and the resizable
// divider. Only mounted when sort = .alphabetical. Click a letter →
// LibraryView selects that letter's first row (List auto-scrolls).
// Letters with zero matches under the current filters are dimmed so the
// user only chases jumps that will land somewhere.

private struct AlphabetJumpBar: View {
    @Environment(AppState.self) private var appState
    let onJump: (Character) -> Void

    private static let letters: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }

    var body: some View {
        let lib = appState.libraryState
        VStack(spacing: 0) {
            ForEach(Self.letters, id: \.self) { letter in
                let key = letter.lowercased()
                let active = lib.availableLetters.contains(key)
                Button {
                    if active, let c = letter.first { onJump(c) }
                } label: {
                    Text(letter)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 1)
                        .foregroundStyle(active ? Color.secondary : Color.secondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(!active)
                .help(active ? "Jump to \(letter)" : "No matches starting with \(letter)")
            }
        }
        .frame(width: 16)
        .padding(.vertical, 6)
        .background(.background.secondary.opacity(0.4))
    }
}

// MARK: - ResizableDivider
//
// A 1pt divider with an 8pt-wide invisible drag region. Drag horizontally to
// resize the parent's `width` binding. The drag region also shows the
// resize cursor on hover.

private struct ResizableDivider: View {
    @Binding var width: CGFloat
    let totalWidth: CGFloat
    @State private var startWidth: CGFloat?

    var body: some View {
        Divider()
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let base = startWidth ?? width
                                if startWidth == nil { startWidth = width }
                                let proposed = base + value.translation.width
                                let softMax = max(LibraryState.widthMin, totalWidth - 360)
                                width = min(
                                    max(proposed, LibraryState.widthMin),
                                    min(LibraryState.widthMax, softMax)
                                )
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            )
    }
}

// MARK: - Word Detail Loader (used by narrow layout's NavigationStack)

private struct WordDetailLoader: View {
    @Environment(AppState.self) private var appState
    let wordId: String
    @State private var word: Word?
    @State private var notFound: Bool = false

    var body: some View {
        Group {
            if let word {
                WordDetailView(word: word, escapeBehavior: .push)
            } else if notFound {
                ContentUnavailableView(
                    "Word not found",
                    systemImage: "questionmark.circle",
                    description: Text("This word is no longer in the database.")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: wordId) {
            await load()
        }
    }

    private func load() async {
        guard let db = appState.databaseService else {
            notFound = true
            return
        }
        do {
            if let w = try db.fetchWord(id: wordId) {
                self.word = w
            } else {
                self.notFound = true
            }
        } catch {
            print("Failed to load word \(wordId): \(error)")
            self.notFound = true
        }
    }
}
