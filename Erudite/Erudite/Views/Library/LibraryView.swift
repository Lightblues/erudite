import SwiftUI

// MARK: - Library View (Word Lists + Browser)
//
// SQL-driven, filtered list of word summaries. All filtering and sorting
// happens in DatabaseService.fetchWordSummaries(); this view only owns the
// search text, picker selections, and the resulting page.
//
// Two layouts depending on width:
// - >= 900pt: Mail-style split (list on left, full WordDetailView on right).
//   Up/Down arrow keys move selection in the list (List(selection:) handles it).
//   Esc clears selection. Cmd+F focuses search; / does too via .searchable's UI.
// - <  900pt: NavigationStack push, like before. Row tap pushes detail page.
//
// The full Word is fetched lazily from the selected wordId so list rendering
// never decodes a 13K-row JSON blob.

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    // Filters
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var selectedTier: FrequencyTier? = nil
    @State private var selectedBookId: String? = nil
    @State private var selectedState: WordStateFilter = .all
    @State private var selectedSort: WordSort = .frequency

    // Results
    @State private var summaries: [WordSummary] = []
    @State private var totalMatching: Int = 0
    @State private var totalAll: Int = 0
    @State private var isLoading: Bool = false
    @State private var loadedCount: Int = 0
    private let pageSize: Int = 200

    // Selection (for split layout)
    @State private var selectedWordId: String? = nil
    @State private var selectedFullWord: Word? = nil

    // Debounce
    @State private var searchDebounceTask: Task<Void, Never>?

    // Layout breakpoint for split vs narrow modes.
    private let splitMinWidth: CGFloat = 900

    var body: some View {
        GeometryReader { geo in
            let isSplit = geo.size.width >= splitMinWidth
            Group {
                if isSplit {
                    splitLayout
                } else {
                    narrowLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, prompt: "Search spelling or definition...")
        .onChange(of: searchText) { _, newValue in
            scheduleSearch(newValue)
        }
        .onChange(of: selectedTier) { _, _ in Task { await reload() } }
        .onChange(of: selectedBookId) { _, _ in Task { await reload() } }
        .onChange(of: selectedState) { _, _ in Task { await reload() } }
        .onChange(of: selectedSort) { _, _ in Task { await reload() } }
        .onChange(of: selectedWordId) { _, newId in
            Task { await loadFullWord(for: newId) }
        }
        // Pending jump from popover Cmd+O / Open in Library: select that word
        // and clear the request token. We also clear filters that might hide it.
        .onChange(of: appState.pendingLibraryWordId) { _, wordId in
            guard let wordId else { return }
            Task { await handlePendingJump(to: wordId) }
        }
        .task {
            await loadTotalCount()
            await reload()
            // If a jump was queued before the view appeared (cold tab switch),
            // honor it now.
            if let wordId = appState.pendingLibraryWordId {
                await handlePendingJump(to: wordId)
            }
        }
    }

    // MARK: - Layouts

    private var splitLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                listPane
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: 320, idealWidth: 380)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: 360)
            }
        }
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
        VStack(spacing: 8) {
            HStack {
                Text("Word Library")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                if !appState.wordBooks.isEmpty {
                    Picker("Book", selection: $selectedBookId) {
                        Text("All Books").tag(String?.none)
                        ForEach(appState.wordBooks) { book in
                            Text(book.name).tag(String?.some(book.id))
                        }
                    }
                    .frame(maxWidth: 200)
                }

                Picker("Tier", selection: $selectedTier) {
                    Text("All").tag(FrequencyTier?.none)
                    Text("Core").tag(FrequencyTier?.some(.core))
                    Text("Common").tag(FrequencyTier?.some(.common))
                    Text("Advanced").tag(FrequencyTier?.some(.advanced))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Picker("State", selection: $selectedState) {
                    ForEach(WordStateFilter.allCases, id: \.self) { state in
                        Text(state.label).tag(state)
                    }
                }
                .frame(maxWidth: 140)

                Picker("Sort", selection: $selectedSort) {
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
        if !appState.isDBReady {
            ProgressView("Loading database...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if summaries.isEmpty && !debouncedSearch.isEmpty {
            ContentUnavailableView.search(text: debouncedSearch)
        } else if summaries.isEmpty {
            ContentUnavailableView(
                "No words match these filters",
                systemImage: "tray",
                description: Text("Try clearing the State or Tier picker.")
            )
        } else {
            VStack(spacing: 0) {
                // Selection binding makes Up/Down move selection automatically.
                List(summaries, selection: $selectedWordId) { summary in
                    WordSummaryRow(summary: summary)
                        .tag(summary.id)
                }
                .listStyle(.inset)
                .onKeyPress(.escape) {
                    if selectedWordId != nil {
                        selectedWordId = nil
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
            if loadedCount < totalMatching {
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
        if totalMatching == 0 { return "No matches" }
        let shown = min(loadedCount, totalMatching)
        if totalMatching >= totalAll {
            return "Showing \(shown) of \(totalMatching)"
        }
        return "Showing \(shown) of \(totalMatching) (total \(totalAll))"
    }

    // MARK: - Detail pane (split layout only)

    @ViewBuilder
    private var detailPane: some View {
        if let word = selectedFullWord {
            WordDetailView(word: word, escapeBehavior: .embedded)
        } else if selectedWordId != nil {
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
        } else if summaries.isEmpty && !debouncedSearch.isEmpty {
            ContentUnavailableView.search(text: debouncedSearch)
        } else if summaries.isEmpty {
            ContentUnavailableView(
                "No words match these filters",
                systemImage: "tray",
                description: Text("Try clearing the State or Tier picker.")
            )
        } else {
            VStack(spacing: 0) {
                List(summaries) { summary in
                    NavigationLink(value: summary.id) {
                        WordSummaryRow(summary: summary)
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
            await MainActor.run { debouncedSearch = value }
            await reload()
        }
    }

    private func loadTotalCount() async {
        guard let db = appState.databaseService else { return }
        totalAll = (try? db.fetchTotalWordCount()) ?? 0
    }

    private func reload() async {
        guard let db = appState.databaseService else { return }
        isLoading = true
        defer { isLoading = false }

        let search = debouncedSearch.isEmpty ? nil : debouncedSearch
        do {
            let count = try db.fetchWordSummaryCount(
                book: selectedBookId,
                tier: selectedTier,
                state: selectedState,
                search: search
            )
            let page = try db.fetchWordSummaries(
                book: selectedBookId,
                tier: selectedTier,
                state: selectedState,
                search: search,
                sort: selectedSort,
                limit: pageSize,
                offset: 0
            )
            self.totalMatching = count
            self.summaries = page
            self.loadedCount = page.count

            // Drop selection if the selected word is no longer in the page.
            if let id = selectedWordId, !page.contains(where: { $0.id == id }) {
                selectedWordId = nil
            }
        } catch {
            print("Library reload failed: \(error)")
            self.summaries = []
            self.totalMatching = 0
            self.loadedCount = 0
        }
    }

    private func loadMore() async {
        guard let db = appState.databaseService else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try db.fetchWordSummaries(
                book: selectedBookId,
                tier: selectedTier,
                state: selectedState,
                search: debouncedSearch.isEmpty ? nil : debouncedSearch,
                sort: selectedSort,
                limit: pageSize,
                offset: loadedCount
            )
            self.summaries.append(contentsOf: page)
            self.loadedCount += page.count
        } catch {
            print("Library loadMore failed: \(error)")
        }
    }

    /// Fetch the full Word for the right-hand detail panel (split layout).
    private func loadFullWord(for wordId: String?) async {
        guard let wordId, let db = appState.databaseService else {
            selectedFullWord = nil
            return
        }
        // Avoid an in-flight flicker if the selection didn't actually change.
        if selectedFullWord?.id == wordId { return }
        do {
            self.selectedFullWord = try db.fetchWord(id: wordId)
        } catch {
            print("Library loadFullWord failed: \(error)")
            self.selectedFullWord = nil
        }
    }

    /// Handle a popover "Open in Library" jump. Clear filters that would hide
    /// the target word, then select it and consume the request.
    private func handlePendingJump(to wordId: String) async {
        // Clear filters most likely to hide the word — book is unsafe to clear
        // because the user might be intentionally narrowing, but tier/state
        // would silently drop it. Search is most likely to hide it.
        if !searchText.isEmpty {
            searchText = ""
            debouncedSearch = ""
        }
        if selectedTier != nil { selectedTier = nil }
        if selectedState != .all { selectedState = .all }

        await reload()

        // If the target isn't in the current page, fetch a single-word summary
        // to seed the detail panel. The list won't show it (book filter etc.),
        // but the user still gets the content they asked for.
        if !summaries.contains(where: { $0.id == wordId }),
           let db = appState.databaseService,
           let word = try? db.fetchWord(id: wordId) {
            self.selectedFullWord = word
        }

        selectedWordId = wordId
        appState.pendingLibraryWordId = nil
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
