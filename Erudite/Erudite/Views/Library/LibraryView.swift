import SwiftUI

// MARK: - Library View (Word Lists + Browser)
//
// SQL-driven, filtered list of word summaries. All filtering and sorting
// happens in DatabaseService.fetchWordSummaries(); this view only owns the
// search text, picker selections, and the resulting page.
//
// State storage:
//   - All "live state" (loaded summaries, selection, filter pickers, scroll
//     position) lives in `AppState.libraryState` so switching tabs doesn't
//     reset the user's place. See LibraryState.
//   - Search-debounce task is a local @State because it's in-flight only.
//
// Layout:
//   - >= 900pt: Mail-style split with a *resizable* divider. List defaults
//     to 360pt (Mail-like), draggable 280–600pt, persisted to UserDefaults.
//     Up/Down arrow keys move selection in the list (List(selection:)
//     handles it). Esc clears selection. Cmd+F focuses search.
//   - <  900pt: NavigationStack push, like before. Row tap pushes detail page.
//
// The full Word is fetched lazily from the selected wordId so list rendering
// never decodes a 13K-row JSON blob.

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    // Search-debounce task. Local because it's only meaningful in-flight;
    // we don't want to pin a Task across tab switches.
    @State private var searchDebounceTask: Task<Void, Never>?

    // Layout breakpoint for split vs narrow modes.
    private let splitMinWidth: CGFloat = 900

    private var lib: LibraryState { appState.libraryState }

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
            Task { await reload() }
        }
        .onChange(of: lib.selectedState) { _, _ in Task { await reload() } }
        .onChange(of: lib.selectedSort) { _, _ in Task { await reload() } }
        .onChange(of: lib.selectedWordId) { _, newId in
            Task { await loadFullWord(for: newId) }
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
                await loadTotalCount()
                await reload()
            } else if lib.summaries.isEmpty {
                // Came back to a state that was emptied — refetch.
                await loadTotalCount()
                await reload()
            }
        }
    }

    // MARK: - Layouts

    /// Split layout with a draggable vertical divider between list and detail.
    /// We use a fixed-width list pane on the left and let the detail pane fill
    /// the remainder — Mail-style. The drag handle lives in the divider's
    /// hit-region so it doesn't compete with row clicks. A vertical A-Z jump
    /// bar sits between the list and the divider.
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
                AlphabetJumpBar(onJump: jumpToLetter)
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
                description: Text("Try clearing the State picker or selecting a different book.")
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

    private var footer: some View {
        HStack(spacing: 12) {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if lib.loadedCount < lib.totalMatching {
                Button("Load More") {
                    Task { await loadMore() }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var footerText: String {
        if lib.totalMatching == 0 { return "No matches" }
        let shown = min(lib.loadedCount, lib.totalMatching)
        if lib.totalMatching >= lib.totalAll {
            return "Showing \(shown) of \(lib.totalMatching)"
        }
        return "Showing \(shown) of \(lib.totalMatching) (total \(lib.totalAll))"
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
                description: Text("Try clearing the State picker or selecting a different book.")
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

    private func loadTotalCount() async {
        guard let db = appState.databaseService else { return }
        lib.totalAll = (try? db.fetchTotalWordCount()) ?? 0
    }

    private func reload() async {
        guard let db = appState.databaseService else { return }
        lib.isLoading = true
        defer { lib.isLoading = false }

        let search = lib.debouncedSearch.isEmpty ? nil : lib.debouncedSearch
        do {
            let count = try db.fetchWordSummaryCount(
                book: lib.selectedBookId,
                state: lib.selectedState,
                search: search
            )
            let page = try db.fetchWordSummaries(
                book: lib.selectedBookId,
                state: lib.selectedState,
                search: search,
                sort: lib.selectedSort,
                limit: pageSize,
                offset: 0
            )
            // Refresh the jump-bar's "available letters" set — used to dim
            // letters with zero matches under the current filters.
            let letters = (try? db.availableStartingLetters(
                book: lib.selectedBookId,
                state: lib.selectedState,
                search: search
            )) ?? []
            lib.totalMatching = count
            lib.summaries = page
            lib.loadedCount = page.count
            lib.availableLetters = letters

            // Drop selection if the selected word is no longer in the page.
            if let id = lib.selectedWordId, !page.contains(where: { $0.id == id }) {
                lib.selectedWordId = nil
            }
        } catch {
            print("Library reload failed: \(error)")
            lib.summaries = []
            lib.totalMatching = 0
            lib.loadedCount = 0
            lib.availableLetters = []
        }
    }

    /// Jump to the first row whose spelling starts with `letter`. If the
    /// current sort isn't alphabetical, switch to it first (the jump bar
    /// only makes sense alphabetized). Loads a page starting at the
    /// computed offset; "Load More" then continues from there.
    private func jumpToLetter(_ letter: Character) {
        Task {
            guard let db = appState.databaseService else { return }
            // Force alphabetical if we're not already there. Reload happens
            // automatically via the .onChange(selectedSort) listener.
            if lib.selectedSort != .alphabetical {
                lib.selectedSort = .alphabetical
                // Wait one tick for the .onChange-driven reload to start so
                // we don't race with it.
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            let search = lib.debouncedSearch.isEmpty ? nil : lib.debouncedSearch
            guard let offset = try? db.offsetForFirstSpelling(
                startingWith: letter,
                book: lib.selectedBookId,
                state: lib.selectedState,
                search: search
            ) else { return }
            // Reload the page starting at that offset. We treat this like
            // a fresh page (loadedCount = pageSize), not a Load-More
            // append, so the user sees only the relevant slice.
            do {
                let page = try db.fetchWordSummaries(
                    book: lib.selectedBookId,
                    state: lib.selectedState,
                    search: search,
                    sort: .alphabetical,
                    limit: pageSize,
                    offset: offset
                )
                lib.summaries = page
                // After a jump, "Load More" should continue from where the
                // jumped page ended.
                lib.loadedCount = offset + page.count
            } catch {
                print("Library jumpToLetter failed: \(error)")
            }
        }
    }

    private func loadMore() async {
        guard let db = appState.databaseService else { return }
        lib.isLoading = true
        defer { lib.isLoading = false }
        do {
            let page = try db.fetchWordSummaries(
                book: lib.selectedBookId,
                state: lib.selectedState,
                search: lib.debouncedSearch.isEmpty ? nil : lib.debouncedSearch,
                sort: lib.selectedSort,
                limit: pageSize,
                offset: lib.loadedCount
            )
            lib.summaries.append(contentsOf: page)
            lib.loadedCount += page.count
        } catch {
            print("Library loadMore failed: \(error)")
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

    private let pageSize: Int = 200
}

// MARK: - AlphabetJumpBar
//
// Vertical strip of A-Z letters between the list pane and the resizable
// divider. Click a letter → LibraryView jumps the page to that letter's
// first row (forcing alphabetical sort if not already). Letters with zero
// matches under the current filters are dimmed so the user only chases
// jumps that will land somewhere.

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
