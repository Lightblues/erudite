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

                quickActions

                Divider()
                    .padding(.horizontal, 32)

                twoColumnPreview
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var quickActions: some View {
        HStack(spacing: 12) {
            ActionButton(title: "Start Learning", icon: "book", color: .blue) {
                appState.startStudy(mode: .mixed)
            }
            ActionButton(title: "Review Due", icon: "arrow.clockwise", color: .green) {
                appState.startStudy(mode: .reviewOnly)
            }
            ActionButton(title: "Type Practice", icon: "keyboard", color: .indigo) {
                appState.selectedTab = .typing
            }
        }
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
        } catch {
            print("Today reload failed: \(error)")
            self.dueSummaries = []
            self.newSummaries = []
        }
    }
}

// MARK: - Preview Row
//
// A tappable row used inside Today's two columns. Tapping opens a popover
// with the full word detail (looked up lazily) so users can peek without
// leaving the home page.

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
