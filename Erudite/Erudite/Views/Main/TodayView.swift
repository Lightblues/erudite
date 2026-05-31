import SwiftUI

// MARK: - Today View (Home / Daily Briefing)
//
// Layout (top → bottom):
//   1. Greeting + date
//   2. Book picker + inline stat strip + progress bar
//   3. Today's homework  (FSRS-driven units the user can pick from)
//   4. Today's recap     (multi-select operation panel for re-practice)
//
// Today is *only* a today-view: what to do, what's been done, what to
// re-practice. Future-due words and the new-word queue belong on Plan;
// they used to live here as a two-column preview but that overlapped
// Plan's own lists and pushed recap below the fold.
//
// The recap section doubles as an operation panel: each row has a
// checkbox (default = needsWork). The bottom CTA pulls the selected
// rows into a StudyQueueBuilder.buildRecapUnit unit (kind = .recap)
// and opens the same UnitPreview sheet the homework rows use. Recap
// sessions don't write back to FSRS (see StudyUnit.Kind.recap).

struct TodayView: View {
    @Environment(AppState.self) private var appState

    @State private var todayUnits: [StudyUnit] = []
    @State private var recapEntries: [DatabaseService.RecapEntry] = []
    /// wordIds the user has selected for re-review. Initialized to the
    /// `needsWork` subset on each reload; the user can toggle individual
    /// rows or hit [Select needsWork] to reset.
    @State private var recapSelection: Set<String> = []
    @State private var previewUnit: StudyUnit?
    @State private var isLoading: Bool = false

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

    // MARK: - Today's recap (multi-select operation panel)
    //
    // List of words touched today via Flashcard rating or Typing
    // completion, sorted "worst first". Each row carries a checkbox;
    // default selection = `needsWork` subset (Again / Hard / mistakes).
    // The bottom CTA materializes the selection into a `.recap` unit
    // that re-uses the same Flashcard/Typing pipeline as homework.

    @ViewBuilder
    private var recapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's recap")
                    .font(.headline)
                Spacer()
                Text(recapHeaderSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(spacing: 0) {
                ForEach(recapEntries) { entry in
                    RecapRow(
                        entry: entry,
                        isSelected: Binding(
                            get: { recapSelection.contains(entry.wordId) },
                            set: { selected in
                                if selected { recapSelection.insert(entry.wordId) }
                                else { recapSelection.remove(entry.wordId) }
                            }
                        )
                    )
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

            recapActions
        }
        .frame(maxWidth: 640)
    }

    private var recapHeaderSummary: String {
        let total = recapEntries.count
        let selected = recapSelection.count
        return "\(selected) / \(total) selected"
    }

    /// Bottom row: [Re-review · K] primary + [Select needsWork] secondary
    /// (only shown when the current selection differs from the default).
    @ViewBuilder
    private var recapActions: some View {
        let needsWorkSet = Set(recapEntries.filter(\.needsWork).map(\.wordId))
        let selectionMatchesDefault = recapSelection == needsWorkSet
        HStack(spacing: 10) {
            if !selectionMatchesDefault, !needsWorkSet.isEmpty {
                Button {
                    recapSelection = needsWorkSet
                } label: {
                    Label("Select needsWork (\(needsWorkSet.count))",
                          systemImage: "wand.and.stars")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
            Button {
                startRecapReview()
            } label: {
                Label("Re-review · \(recapSelection.count)",
                      systemImage: "arrow.uturn.left.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .controlSize(.regular)
            .disabled(recapSelection.isEmpty)
        }
        .padding(.top, 4)
    }

    private func startRecapReview() {
        guard let db = appState.databaseService else { return }
        let selected = recapEntries.filter { recapSelection.contains($0.wordId) }
        guard !selected.isEmpty else { return }
        let builder = StudyQueueBuilder(db: db)
        if let unit = try? builder.buildRecapUnit(from: selected) {
            previewUnit = unit
        }
    }

    // MARK: - Reload

    private func reload() async {
        guard appState.isDBReady, let db = appState.databaseService else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let builder = StudyQueueBuilder(db: db)
            self.todayUnits = (try? builder.buildTodayUnits(
                bookId: appState.activeBookId,
                unitSize: appState.settings.unitSize
            )) ?? []

            let entries = (try? db.fetchTodayRecap()) ?? []
            self.recapEntries = entries
            // Default selection: the needsWork subset — the user can
            // still uncheck rows or [Select needsWork] to reset.
            self.recapSelection = Set(entries.filter(\.needsWork).map(\.wordId))
        } catch {
            print("Today reload failed: \(error)")
            self.todayUnits = []
            self.recapEntries = []
            self.recapSelection = []
        }
    }
}

// MARK: - Recap Row
//
// One row in the "Today's recap" list. Shows: checkbox + spelling +
// chinese def + a pressing-signal badge (Again / Hard / N mistakes /
// Good / Typed). Tapping the body opens a popover with the full word
// card; toggling the checkbox enrolls/unenrolls the row from the
// pending re-review unit.

private struct RecapRow: View {
    @Environment(AppState.self) private var appState
    let entry: DatabaseService.RecapEntry
    @Binding var isSelected: Bool

    @State private var showPopover: Bool = false
    @State private var fullWord: Word?

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox: tappable target outside the popover button so
            // toggling the selection doesn't open the popover.
            Button {
                isSelected.toggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

