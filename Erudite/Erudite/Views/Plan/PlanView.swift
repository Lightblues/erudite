import SwiftUI
import Charts

// MARK: - Plan View
//
// Two-region layout:
//
//   ┌─────────────────────────────────────────┐
//   │  Roadmap  (active book ETA)             │  fixed top
//   │  7-Day Workload  (Swift Charts)         │
//   ├─────────────────────────────────────────┤
//   │  [Today · 18][Tomorrow · 24]…[New · 50] │  segmented tabs
//   │  ─────────────────────────────────      │
//   │  selected bucket's word list             │  scrolls independently
//   │  …                                       │
//   └─────────────────────────────────────────┘
//
// The previous layout stacked Roadmap + Chart + a New Words section +
// a Due Backlog disclosure tree in one ScrollView, which made the
// page tens of screens tall and forced users to scroll past the
// chart every time they wanted to see Tomorrow's words. Tab-segmenting
// the worklist lets each bucket render full-height and keeps the
// overview always visible up top.
//
// Bucket model:
// - `Today` merges DueBucket.overdue + .today (overdue is highlighted
//   with a red marker so the user still notices it)
// - `Tomorrow` / `This Week` / `Later` mirror DueBucket directly
// - `New` is the next 50 words from book sortOrder — same data the
//   Today tab used to show in its right column

struct PlanView: View {
    @Environment(AppState.self) private var appState

    @State private var dueByDay: [(date: Date, count: Int)] = []
    @State private var newQueue: [WordSummary] = []
    @State private var backlog: [DatabaseService.DueBucket: [WordSummary]] = [:]
    @State private var backlogCounts: [DatabaseService.DueBucket: Int] = [:]
    @State private var selectedTab: WorklistTab = .today
    @State private var isLoading: Bool = false

    var body: some View {
        // Wrap in NavigationStack so .navigationDestination(for:) resolves
        // (NavigationSplitView's detail column doesn't supply its own stack).
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                overviewHeader
                Divider()
                worklistTabBar
                Divider()
                worklistList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationDestination(for: String.self) { wordId in
                PlanWordDetailLoader(wordId: wordId)
            }
            .task {
                await reload()
            }
            .onChange(of: appState.activeBookId) { _, _ in
                Task { await reload() }
            }
            .onChange(of: appState.isDBReady) { _, ready in
                if ready { Task { await reload() } }
            }
        }
    }

    // MARK: - Top: title + Roadmap + Chart (fixed; doesn't scroll with list)

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Plan")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            roadmapSection
            workloadSection
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Section 1: Roadmap

    private var roadmapSection: some View {
        sectionCard(title: "Roadmap", systemImage: "map") {
            if let book = appState.activeBook {
                roadmapForBook(book)
            } else {
                Text("Select a word book on the Today page to see roadmap progress.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func roadmapForBook(_ book: WordBook) -> some View {
        let total = book.wordCount
        let learned = appState.learnedCount
        let remaining = max(0, total - learned)
        let dailyNew = 10  // matches Scheduler.parameters.dailyNewLimit
        let etaDays = remaining > 0 ? Int(ceil(Double(remaining) / Double(dailyNew))) : 0
        let fraction = total > 0 ? Double(learned) / Double(total) : 0

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(book.name)
                    .font(.headline)
                Spacer()
                Text("\(learned) / \(total)")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                Text("(\(Int(fraction * 100))%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.green.opacity(0.15))
                    Capsule().fill(Color.green)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 10)

            if remaining > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("At \(dailyNew) new words/day, ETA: ~\(etaDays) days")
                        .font(.callout)
                    Spacer()
                }
                Text("Estimate varies with review accuracy and daily pace.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Label("Book complete!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
        }
    }

    // MARK: - Section 2: 7-Day Workload (Swift Charts)

    private var workloadSection: some View {
        sectionCard(title: "7-Day Workload", systemImage: "chart.bar") {
            if dueByDay.isEmpty || dueByDay.allSatisfy({ $0.count == 0 }) {
                Text("No reviews scheduled in the next 7 days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart(Array(dueByDay.enumerated()), id: \.offset) { _, entry in
                    BarMark(
                        x: .value("Day", entry.date, unit: .day),
                        y: .value("Reviews", entry.count)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .annotation(position: .top, alignment: .center) {
                        if entry.count > 0 {
                            Text("\(entry.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .font(.caption)
                    }
                }
                .frame(height: 140)

                Text("Review counts are a snapshot — each rating you give shifts future due dates.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Worklist tab bar (segmented control with counts)
    //
    // Picker(.segmented) does the job for the picker UI; we wrap it in
    // a custom row so each segment can show "Today · 18" with a colored
    // count, which the native segmented style can't surface.

    private var worklistTabBar: some View {
        HStack(spacing: 6) {
            ForEach(WorklistTab.allCases, id: \.self) { tab in
                worklistTabButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private func worklistTabButton(_ tab: WorklistTab) -> some View {
        let count = countFor(tab)
        let active = (selectedTab == tab)
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(tab.label)
                    .font(.subheadline.weight(active ? .semibold : .regular))
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(active ? .white : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(active ? tab.tint : Color.secondary.opacity(0.15))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? tab.tint.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(active ? tab.tint.opacity(0.5) : Color.secondary.opacity(0.2),
                            lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ tab: WorklistTab) -> Int {
        switch tab {
        case .today:
            return (backlogCounts[.overdue] ?? 0) + (backlogCounts[.today] ?? 0)
        case .tomorrow:
            return backlogCounts[.tomorrow] ?? 0
        case .thisWeek:
            return backlogCounts[.thisWeek] ?? 0
        case .later:
            return backlogCounts[.later] ?? 0
        case .new:
            return newQueue.count
        }
    }

    // MARK: - Worklist list (full-height, scrolls independently)

    @ViewBuilder
    private var worklistList: some View {
        let summaries = summariesFor(selectedTab)
        if summaries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: selectedTab.emptyIcon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(selectedTab.emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        NavigationLink(value: summary.id) {
                            HStack(spacing: 10) {
                                if selectedTab == .new {
                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 28, alignment: .trailing)
                                        .monospacedDigit()
                                } else if selectedTab == .today,
                                          let due = summary.dueDate,
                                          due < Calendar.current.startOfDay(for: Date()) {
                                    // Overdue marker — flag past-due words
                                    // inside the merged Today tab.
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                        .frame(width: 28)
                                } else {
                                    Color.clear.frame(width: 28)
                                }
                                WordSummaryRow(summary: summary, density: .compact, showStateBadge: false)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private func summariesFor(_ tab: WorklistTab) -> [WordSummary] {
        switch tab {
        case .today:
            // Merge overdue + today; overdue first so the user sees
            // what's most urgent. Both share the "needs to be done now"
            // mental model, no point splitting them into two tabs.
            return (backlog[.overdue] ?? []) + (backlog[.today] ?? [])
        case .tomorrow:
            return backlog[.tomorrow] ?? []
        case .thisWeek:
            return backlog[.thisWeek] ?? []
        case .later:
            return backlog[.later] ?? []
        case .new:
            return newQueue
        }
    }

    // MARK: - Section card shell

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Reload

    private func reload() async {
        guard appState.isDBReady, let db = appState.databaseService else { return }
        isLoading = true
        defer { isLoading = false }

        let bookId = appState.activeBookId
        do {
            self.dueByDay = try db.fetchDueCountsByDay(daysAhead: 7, inBook: bookId)
            self.newQueue = try db.fetchNewWordSummaries(inBook: bookId, limit: 50)
            self.backlog = try db.fetchDueBacklog(inBook: bookId, perBucketLimit: 100)
            self.backlogCounts = try db.fetchDueBacklogCounts(inBook: bookId)
        } catch {
            print("Plan reload failed: \(error)")
        }
    }
}

// MARK: - Worklist tabs
//
// The visible tabs in Plan's worklist segment. `Today` merges the
// underlying DueBucket.overdue + .today; everything else is 1:1.
// Order: Today → Tomorrow → This Week → Later → New (queued, not
// yet scheduled).

private enum WorklistTab: String, CaseIterable, Hashable {
    case today, tomorrow, thisWeek, later, new

    var label: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "This week"
        case .later: "Later"
        case .new: "New"
        }
    }

    var tint: Color {
        switch self {
        case .today: .orange
        case .tomorrow: .yellow
        case .thisWeek: .green
        case .later: .gray
        case .new: .blue
        }
    }

    var emptyMessage: String {
        switch self {
        case .today: "Nothing due today. Nice."
        case .tomorrow: "Tomorrow is open."
        case .thisWeek: "Nothing scheduled this week."
        case .later: "Nothing scheduled for next week."
        case .new: "No new words remaining in this book."
        }
    }

    var emptyIcon: String {
        switch self {
        case .today: "checkmark.seal"
        case .tomorrow, .thisWeek, .later: "calendar"
        case .new: "tray"
        }
    }
}

// MARK: - Detail loader (mirrors LibraryView's)

private struct PlanWordDetailLoader: View {
    @Environment(AppState.self) private var appState
    let wordId: String
    @State private var word: Word?

    var body: some View {
        Group {
            if let word {
                WordDetailView(word: word)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: wordId) {
            guard let db = appState.databaseService else { return }
            self.word = try? db.fetchWord(id: wordId)
        }
    }
}
