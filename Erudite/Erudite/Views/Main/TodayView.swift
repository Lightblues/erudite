import SwiftUI

// MARK: - Today View (Home / Daily Briefing)
//
// Layout (top → bottom):
//   1. Greeting + date
//   2. Book picker + inline stat strip + progress bar
//   3. Quick action buttons
//   4. Two-column preview (Reviews | New) — main information density
//
// All preview rows are WordSummary-driven; clicking a row opens a popover
// with the full word detail (lazy lookup). The previous "All caught up!"
// card is gone — empty columns show a small inline message instead.

struct TodayView: View {
    @Environment(AppState.self) private var appState

    @State private var dueSummaries: [WordSummary] = []
    @State private var newSummaries: [WordSummary] = []
    @State private var todayUnits: [StudyUnit] = []
    @State private var recapEntries: [DatabaseService.RecapEntry] = []
    @State private var previewUnit: StudyUnit?
    @State private var isLoading: Bool = false

    private let previewLimit: Int = 50

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                greeting
                    .padding(.top, 24)

                if !appState.wordBooks.isEmpty {
                    bookPicker
                }

                statsStrip

                if let book = appState.activeBook {
                    bookProgress(book: book)
                }

                homeworkSection

                if !recapEntries.isEmpty {
                    Divider()
                        .padding(.horizontal, 32)
                    recapSection
                }

                Divider()
                    .padding(.horizontal, 32)

                twoColumnPreview
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $previewUnit) { unit in
            UnitPreviewView(unit: unit)
        }
        .task {
            appState.refreshStats()
            await reload()
        }
        .onChange(of: appState.activeBookId) { _, _ in
            Task { await reload() }
        }
        .onChange(of: appState.isDBReady) { _, ready in
            if ready { Task { await reload() } }
        }
        .onChange(of: appState.settings.unitSize) { _, _ in
            Task { await reload() }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(spacing: 4) {
            Text("Good \(greetingTime)!")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var greetingTime: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }

    private var bookPicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed")
                .foregroundStyle(.secondary)
            Picker("Word Book", selection: Binding(
                get: { appState.activeBookId },
                set: { appState.selectBook($0) }
            )) {
                Text("All Books").tag(String?.none)
                Divider()
                ForEach(appState.wordBooks) { book in
                    HStack {
                        Text(book.name)
                        if let exam = book.exam {
                            Text("(\(exam))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(String?.some(book.id))
                }
            }
            .frame(maxWidth: 320)
        }
    }

    // MARK: - Stats strip (replaces the bulky StatBadge column layout)

    private var statsStrip: some View {
        HStack(spacing: 24) {
            stat(icon: "checkmark.circle.fill", color: .green, value: appState.learnedCount, label: "Learned")
            stat(icon: "arrow.clockwise", color: .orange, value: appState.dueCount, label: "Due")
            stat(icon: "plus.circle", color: .blue, value: appState.newCount, label: "Remaining")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stat(icon: String, color: Color, value: Int, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bookProgress(book: WordBook) -> some View {
        let total = book.wordCount
        let learned = appState.learnedCount
        let fraction = total > 0 ? Double(learned) / Double(total) : 0

        return VStack(spacing: 6) {
            HStack {
                Text(book.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(learned) / \(total)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("(\(Int(fraction * 100))%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                    Capsule()
                        .fill(Color.green)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: 480)
    }

    // MARK: - Today's homework (FSRS-driven only)
    //
    // The list of FSRS-driven study units the user can pick from today.
    // Book Chapters are NOT shown here — they live in Library now under
    // its Chapter view. "Homework" is a stricter promise: this is what
    // the scheduler says you need to do today.

    private var homeworkSection: some View {
        UnitPickerView(
            units: todayUnits,
            onPick: { previewUnit = $0 },
            header: "Today's homework",
            emptyTitle: "All caught up!",
            emptyMessage: "No reviews due. New words will appear when the queue refreshes."
        )
        .frame(maxWidth: 640)
    }

    // MARK: - Today's recap
    //
    // List of words touched today via Flashcard rating or Typing
    // completion, sorted "worst first" so the user's eye lands on what
    // needs another look. Tapping a row opens a popover with the full
    // word card.

    @ViewBuilder
    private var recapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's recap")
                    .font(.headline)
                Spacer()
                Text(recapSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(recapEntries) { entry in
                    RecapRow(entry: entry)
                    if entry.id != recapEntries.last?.id {
                        Divider()
                    }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.quaternary, lineWidth: 0.5)
            )
        }
        .frame(maxWidth: 640)
    }

    private var recapSummary: String {
        let totalWords = recapEntries.count
        let again = recapEntries.filter { $0.latestRating == .again }.count
        if again > 0 {
            return "\(totalWords) words · \(again) need another look"
        }
        return "\(totalWords) words touched today"
    }

    // MARK: - Two-column preview

    private var twoColumnPreview: some View {
        HStack(alignment: .top, spacing: 16) {
            previewColumn(
                title: "Reviews",
                count: appState.dueCount,
                summaries: dueSummaries,
                tint: .orange,
                emptyMessage: "No reviews due. Nice."
            )

            previewColumn(
                title: "New",
                count: appState.newCount,
                summaries: newSummaries,
                tint: .blue,
                emptyMessage: "No new words queued."
            )
        }
        .frame(maxHeight: 480)
    }

    @ViewBuilder
    private func previewColumn(
        title: String,
        count: Int,
        summaries: [WordSummary],
        tint: Color,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: title == "Reviews" ? "arrow.clockwise.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                Text("(\(count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.08))

            if summaries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(summaries) { summary in
                            PreviewRow(
                                summary: summary,
                                trailing: trailingLabel(for: summary, columnTitle: title)
                            )
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Reviews column shows "today" / "1d late" / "in 2d"; New column has no trailing.
    private func trailingLabel(for summary: WordSummary, columnTitle: String) -> String? {
        guard columnTitle == "Reviews", let due = summary.dueDate else { return nil }
        return DueDateFormatter.relativeLabel(for: due)
    }

    // MARK: - Reload

    private func reload() async {
        guard appState.isDBReady, let db = appState.databaseService else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let due = try db.fetchDueSummaries(inBook: appState.activeBookId, limit: previewLimit)
            let new = try db.fetchNewWordSummaries(inBook: appState.activeBookId, limit: previewLimit)
            self.dueSummaries = due
            self.newSummaries = new

            let builder = StudyQueueBuilder(db: db)
            self.todayUnits = (try? builder.buildTodayUnits(
                bookId: appState.activeBookId,
                unitSize: appState.settings.unitSize
            )) ?? []

            self.recapEntries = (try? db.fetchTodayRecap()) ?? []
        } catch {
            print("Today reload failed: \(error)")
            self.dueSummaries = []
            self.newSummaries = []
            self.todayUnits = []
            self.recapEntries = []
        }
    }
}

// MARK: - Preview Row
//
// A tappable row used inside Today's two columns. Tapping opens a popover
// with the full word detail (looked up lazily) so users can peek without
// leaving the home page.

// MARK: - Recap Row
//
// One row in the "Today's recap" list. Shows spelling + chinese def + a
// pressing-signal badge (Again × N / Hard / N mistakes / Good).
// Tapping opens a popover with the full word card so the user can
// re-look-at problem words without leaving Today.

private struct RecapRow: View {
    @Environment(AppState.self) private var appState
    let entry: DatabaseService.RecapEntry

    @State private var showPopover: Bool = false
    @State private var fullWord: Word?

    var body: some View {
        Button {
            showPopover = true
            Task { await loadWord() }
        } label: {
            HStack(spacing: 10) {
                badge
                    .frame(width: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.spelling)
                        .font(.subheadline.weight(.semibold))
                    if let def = entry.firstDefZh {
                        Text(def)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if entry.attempts > 1 {
                    Text("× \(entry.attempts)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            if let word = fullWord {
                WordPopoverView(word: word) { showPopover = false }
            } else {
                ProgressView().padding(40)
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        let (color, label): (Color, String) = badgeFor(entry)
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func badgeFor(_ e: DatabaseService.RecapEntry) -> (Color, String) {
        if e.latestRating == .again { return (.red, "Again") }
        if e.latestRating == .hard { return (.orange, "Hard") }
        if e.latestRating == .good { return (.green, "Good") }
        if e.latestRating == .easy { return (.blue, "Easy") }
        // Typing-only paths
        if e.typingMistakes >= 3 { return (.red, "\(e.typingMistakes) miss") }
        if e.typingMistakes > 0 { return (.orange, "\(e.typingMistakes) miss") }
        return (.green, "Typed")
    }

    private func loadWord() async {
        guard fullWord == nil, let db = appState.databaseService else { return }
        if let w = try? db.fetchWord(id: entry.wordId) {
            fullWord = w
        }
    }
}

private struct PreviewRow: View {
    @Environment(AppState.self) private var appState
    let summary: WordSummary
    let trailing: String?

    @State private var showPopover: Bool = false
    @State private var fullWord: Word?

    var body: some View {
        Button {
            showPopover = true
            Task { await loadWord() }
        } label: {
            WordSummaryRow(
                summary: summary,
                density: .compact,
                showStateBadge: false,
                trailingText: trailing
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            popoverContent
                .frame(width: 380)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        if let word = fullWord {
            WordPopoverView(word: word) { showPopover = false }
        } else {
            VStack {
                ProgressView()
                Text(summary.spelling)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 280, height: 120)
        }
    }

    private func loadWord() async {
        guard fullWord == nil, let db = appState.databaseService else { return }
        if let word = try? db.fetchWord(id: summary.id) {
            self.fullWord = word
        }
    }
}

// MARK: - Action Button (unchanged)

private struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(width: 140)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .controlSize(.large)
    }
}
