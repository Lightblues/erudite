import SwiftUI

// MARK: - Library View (Word Lists + Browser)
//
// Renders a SQL-driven, filtered list of word summaries. All filtering and
// sorting happens in DatabaseService.fetchWordSummaries(); this view only
// owns the search text, picker selections, and the resulting page.
//
// The full Word is fetched lazily inside WordDetailView when the user
// navigates into a row — list rows never decode the full JSON blob.

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

    // Debounce
    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $searchText, prompt: "Search spelling or definition...")
        .onChange(of: searchText) { _, newValue in
            scheduleSearch(newValue)
        }
        .onChange(of: selectedTier) { _, _ in Task { await reload() } }
        .onChange(of: selectedBookId) { _, _ in Task { await reload() } }
        .onChange(of: selectedState) { _, _ in Task { await reload() } }
        .onChange(of: selectedSort) { _, _ in Task { await reload() } }
        .task {
            await loadTotalCount()
            await reload()
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
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
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(summaries) { summary in
                NavigationLink(value: summary.id) {
                    WordSummaryRow(summary: summary)
                }
            }
            .listStyle(.inset)
            .navigationDestination(for: String.self) { wordId in
                WordDetailLoader(wordId: wordId)
            }

            // Footer: count + load more
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
    }

    private var footerText: String {
        if totalMatching == 0 { return "No matches" }
        let shown = min(loadedCount, totalMatching)
        if totalMatching > totalAll {
            return "Showing \(shown) of \(totalMatching)"
        }
        return "Showing \(shown) of \(totalMatching) (total \(totalAll))"
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
}

// MARK: - Word Detail Loader
//
// Resolves the full Word from the database when the user navigates into a
// row. Keeps WordDetailView agnostic of the loading strategy.

private struct WordDetailLoader: View {
    @Environment(AppState.self) private var appState
    let wordId: String
    @State private var word: Word?
    @State private var notFound: Bool = false

    var body: some View {
        Group {
            if let word {
                WordDetailView(word: word)
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
