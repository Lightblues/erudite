import SwiftUI
import Charts

// MARK: - Plan View
//
// Four sections, each independently fetched and rendered:
//   1. Roadmap          — overall progress + ETA for the active book
//   2. 7-Day Workload   — bar chart of upcoming due-card load (Swift Charts)
//   3. New Words Queue  — next 50 words from book sortOrder
//   4. Due Backlog      — disclosure groups by time bucket (Today/Tomorrow/...)
//
// Loads live for the active book; "All Books" shows the global view.

struct PlanView: View {
    @Environment(AppState.self) private var appState

    @State private var dueByDay: [(date: Date, count: Int)] = []
    @State private var newQueue: [WordSummary] = []
    @State private var backlog: [DatabaseService.DueBucket: [WordSummary]] = [:]
    @State private var backlogCounts: [DatabaseService.DueBucket: Int] = [:]
    @State private var isLoading: Bool = false

    var body: some View {
        // Wrap in NavigationStack so .navigationDestination(for:) resolves
        // (NavigationSplitView's detail column doesn't supply its own stack).
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    title
                    roadmapSection
                    workloadSection
                    newQueueSection
                    backlogSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationDestination(for: String.self) { wordId in
                // Reuse Library's loader pattern by going through a small wrapper
                // (kept inside this file to avoid exporting another type)
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

    // MARK: - Title

    private var title: some View {
        HStack {
            Text("Plan")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
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
                .frame(height: 180)

                Text("Review counts are a snapshot — each rating you give shifts future due dates.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Section 3: New Words Queue

    private var newQueueSection: some View {
        sectionCard(title: "New Words Queue", systemImage: "tray") {
            if newQueue.isEmpty {
                Text("No new words remaining in this book.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Next \(newQueue.count) — in book order")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)

                    ForEach(Array(newQueue.enumerated()), id: \.element.id) { index, summary in
                        NavigationLink(value: summary.id) {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 28, alignment: .trailing)
                                    .monospacedDigit()
                                WordSummaryRow(summary: summary, density: .compact, showStateBadge: false)
                            }
                        }
                        .buttonStyle(.plain)
                        if index < newQueue.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Section 4: Due Backlog

    private var backlogSection: some View {
        sectionCard(title: "Due Backlog", systemImage: "tray.full") {
            if backlogCounts.isEmpty {
                Text("Nothing due in the next 30 days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(DatabaseService.DueBucket.allCases, id: \.rawValue) { bucket in
                        if let count = backlogCounts[bucket], count > 0 {
                            backlogGroup(bucket: bucket, count: count)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func backlogGroup(bucket: DatabaseService.DueBucket, count: Int) -> some View {
        let summaries = backlog[bucket] ?? []
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(summaries) { summary in
                    NavigationLink(value: summary.id) {
                        WordSummaryRow(summary: summary, density: .compact, showStateBadge: false)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                if summaries.count < count {
                    Text("… and \(count - summaries.count) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
            }
            .padding(.leading, 8)
        } label: {
            HStack {
                if bucket == .overdue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Text(bucket.label)
                    .font(.callout)
                    .fontWeight(bucket == .today || bucket == .overdue ? .semibold : .regular)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
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
            self.backlog = try db.fetchDueBacklog(inBook: bookId, perBucketLimit: 30)
            self.backlogCounts = try db.fetchDueBacklogCounts(inBook: bookId)
        } catch {
            print("Plan reload failed: \(error)")
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
