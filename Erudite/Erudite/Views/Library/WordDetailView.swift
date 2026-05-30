import SwiftUI

// MARK: - Word Detail View
//
// Sections (top to bottom):
//   • Header (spelling + IPA + tier)
//   • Learning Progress (FSRS state, recent ratings, books)   — NEW
//   • Definitions
//   • Examples
//   • Mnemonics (builtin from word.mnemonics + user from user_content) — NEW edit
//   • Synonyms
//   • Word Roots
//   • Metadata
//
// Learning Progress is read-only in v1. Mnemonics: builtin entries are
// non-editable (rebuilt from bundled data); user entries can be added,
// edited, or deleted.

struct WordDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let word: Word

    /// Esc behavior depends on host:
    /// - `.push` (default): pop the navigation stack via @Environment(\.dismiss)
    /// - `.embedded`: do nothing — the host (e.g. Library split view) handles Esc
    ///   to clear selection instead, and we don't want a double-action.
    var escapeBehavior: EscapeBehavior = .push

    enum EscapeBehavior {
        case push
        case embedded
    }

    @State private var card: ReviewCard?
    @State private var recentLogs: [ReviewLog] = []
    @State private var containingBooks: [WordBook] = []
    @State private var userMnemonics: [DatabaseService.UserContent] = []
    @State private var showAddMnemonic: Bool = false
    @State private var editingMnemonic: DatabaseService.UserContent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()

                learningProgressSection

                definitionsSection

                if !word.examples.isEmpty {
                    examplesSection
                }

                mnemonicsSection

                if !word.synonymGroups.isEmpty {
                    synonymsSection
                }

                if let roots = word.roots {
                    rootsSection(roots)
                }

                metadataSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(word.spelling)
        .task(id: word.id) { await loadAuxiliaryData() }
        .sheet(isPresented: $showAddMnemonic) {
            MnemonicEditor(
                wordId: word.id,
                existing: nil,
                onSave: { _ in Task { await reloadUserMnemonics() } }
            )
        }
        .sheet(item: $editingMnemonic) { mnemonic in
            MnemonicEditor(
                wordId: word.id,
                existing: mnemonic,
                onSave: { _ in Task { await reloadUserMnemonics() } }
            )
        }
        // Esc dismisses when pushed onto a navigation stack. We focusable() so
        // the modifier reliably receives keys even though the page is mostly
        // scrollable text (no native focus targets).
        .focusable(escapeBehavior == .push)
        .onKeyPress(.escape) {
            if escapeBehavior == .push {
                dismiss()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(word.spelling)
                    .font(.system(size: 32, weight: .bold, design: .serif))

                if let phonetic = word.phonetic {
                    Text(phonetic)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                tierBadge(word.frequency)
            }
        }
    }

    // MARK: - Learning Progress (NEW)

    private var learningProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Learning Progress", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            GroupBox {
                if let card {
                    VStack(alignment: .leading, spacing: 10) {
                        // Top row: state + due
                        HStack(spacing: 16) {
                            stateBadge(card.state)
                            Text(dueText(card))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        // Stats row
                        HStack(spacing: 24) {
                            statBlock("Reps", value: "\(card.reps)")
                            statBlock("Lapses", value: "\(card.lapses)", color: card.lapses > 0 ? .orange : nil)
                            statBlock("Accuracy", value: accuracyText)
                            statBlock("Stability", value: String(format: "%.1f d", card.stability))
                            statBlock("Difficulty", value: String(format: "%.1f", card.difficulty))
                        }

                        // Recent ratings tape
                        if !recentLogs.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Recent reviews")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    ForEach(recentLogs) { log in
                                        ratingChip(log.rating)
                                            .help(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    }
                                }
                            }
                        }

                        // Books
                        if !containingBooks.isEmpty {
                            Divider()
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Books")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                FlowHStack(spacing: 6) {
                                    ForEach(containingBooks) { book in
                                        Text(book.name)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(.blue.opacity(0.1), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(4)
                } else {
                    Text("This word does not have a review card yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
            }
        }
    }

    private func dueText(_ card: ReviewCard) -> String {
        if card.state == .new {
            return "New — not yet scheduled"
        }
        let cal = Calendar.current
        let now = Date()
        let dueDay = cal.startOfDay(for: card.dueDate)
        let nowDay = cal.startOfDay(for: now)
        let days = cal.dateComponents([.day], from: nowDay, to: dueDay).day ?? 0
        if days < 0 {
            return "Overdue by \(-days) day\(-days == 1 ? "" : "s")"
        } else if days == 0 {
            return "Due today"
        } else if days == 1 {
            return "Due tomorrow"
        } else {
            return "Due in \(days) days"
        }
    }

    private var accuracyText: String {
        if recentLogs.isEmpty { return "—" }
        let correct = recentLogs.filter { $0.rating == .good || $0.rating == .easy }.count
        let pct = Int((Double(correct) / Double(recentLogs.count)) * 100)
        return "\(pct)%"
    }

    private func statBlock(_ label: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(color ?? .primary)
        }
    }

    private func stateBadge(_ state: CardState) -> some View {
        let (color, label): (Color, String) = switch state {
        case .new: (.gray, "New")
        case .learning: (.orange, "Learning")
        case .review: (.green, "Review")
        case .relearning: (.red, "Relearning")
        }
        return Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func ratingChip(_ rating: Rating) -> some View {
        let (color, glyph): (Color, String) = switch rating {
        case .again: (.red, "✗")
        case .hard: (.orange, "~")
        case .good: (.green, "✓")
        case .easy: (.blue, "⚡")
        }
        return Text(glyph)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Definitions

    private var definitionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Definitions", systemImage: "text.book.closed")
                .font(.headline)

            ForEach(Array(word.definitions.enumerated()), id: \.offset) { _, def in
                HStack(alignment: .top, spacing: 10) {
                    if !def.partOfSpeech.isEmpty {
                        Text(def.partOfSpeech)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(def.chinese)
                            .font(.body)
                        if !def.english.isEmpty {
                            InteractiveText(text: def.english, font: .callout, color: .secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Examples

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Examples", systemImage: "text.quote")
                .font(.headline)

            ForEach(Array(word.examples.enumerated()), id: \.offset) { _, example in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        InteractiveText(text: example.sentence, font: .callout, color: .secondary, italic: true)
                        Text(example.source)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Mnemonics (now: builtin + user)

    private var mnemonicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Mnemonics", systemImage: "lightbulb")
                    .font(.headline)
                Spacer()
                Button {
                    showAddMnemonic = true
                } label: {
                    Label("Add yours", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Builtin mnemonics (from bundled data — not editable)
            ForEach(word.mnemonics, id: \.self) { mnemonic in
                mnemonicCard(text: mnemonic, source: .builtin, onEdit: nil, onDelete: nil)
            }

            // User mnemonics (editable)
            ForEach(userMnemonics) { entry in
                mnemonicCard(
                    text: entry.content,
                    source: .user(date: entry.updatedAt),
                    onEdit: { editingMnemonic = entry },
                    onDelete: { Task { await deleteMnemonic(entry) } }
                )
            }

            if word.mnemonics.isEmpty && userMnemonics.isEmpty {
                Text("No mnemonics yet. Click \"Add yours\" to write one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    private enum MnemonicSource {
        case builtin
        case user(date: Date)
    }

    @ViewBuilder
    private func mnemonicCard(
        text: String,
        source: MnemonicSource,
        onEdit: (() -> Void)?,
        onDelete: (() -> Void)?
    ) -> some View {
        let (icon, tint, backgroundTint, label): (String, Color, Color, String) = switch source {
        case .builtin: ("lightbulb.fill", .yellow, .yellow, "builtin")
        case .user: ("pencil.circle.fill", .purple, .purple, "yours")
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.caption)
                InteractiveText(text: text, font: .callout, color: .primary.opacity(0.85))
                Spacer()
                if let onEdit {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                if let onDelete {
                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(tint)
                if case .user(let date) = source {
                    Text("· \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Synonyms

    private var synonymsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Synonyms", systemImage: "link")
                .font(.headline)

            ForEach(Array(word.synonymGroups.enumerated()), id: \.offset) { _, group in
                SynonymChipsView(synonyms: group, chipFont: .callout, chipPaddingH: 10, chipPaddingV: 4)
            }
        }
    }

    // MARK: - Roots

    private func rootsSection(_ roots: MorphemeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Word Roots", systemImage: "tree")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(Array(roots.segments.enumerated()), id: \.offset) { _, segment in
                    VStack(spacing: 2) {
                        Text(segment.text)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(segment.meaning)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(segment.type.rawValue)
                            .font(.caption2)
                            .foregroundStyle(morphemeColor(segment.type))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(morphemeColor(segment.type).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Text(roots.logic)
                .font(.callout)
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Info", systemImage: "info.circle")
                .font(.headline)

            HStack(spacing: 16) {
                metaItem("Frequency", value: word.frequency.label)
                metaItem("Sentiment", value: word.sentiment.rawValue)
                if !word.tags.isEmpty {
                    metaItem("Tags", value: word.tags.joined(separator: ", "))
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func tierBadge(_ tier: FrequencyTier) -> some View {
        Text(tier.label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tierColor(tier).opacity(0.15), in: Capsule())
            .foregroundStyle(tierColor(tier))
    }

    private func tierColor(_ tier: FrequencyTier) -> Color {
        switch tier {
        case .core: .red
        case .common: .blue
        case .advanced: .gray
        }
    }

    private func morphemeColor(_ type: MorphemeType) -> Color {
        switch type {
        case .prefix: .purple
        case .root: .blue
        case .suffix: .green
        }
    }

    private func metaItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    // MARK: - Data loading

    private func loadAuxiliaryData() async {
        guard let db = appState.databaseService else { return }
        do {
            let card = try db.fetchReviewCard(forWord: word.id)
            self.card = card
            if let card {
                self.recentLogs = try db.fetchReviewLogs(cardId: card.id, limit: 8)
            } else {
                self.recentLogs = []
            }
            self.containingBooks = try db.fetchBooks(containingWord: word.id)
            self.userMnemonics = try db.fetchUserContent(wordId: word.id, type: "mnemonic")
        } catch {
            print("Failed to load word detail aux data: \(error)")
        }
    }

    private func reloadUserMnemonics() async {
        guard let db = appState.databaseService else { return }
        if let updated = try? db.fetchUserContent(wordId: word.id, type: "mnemonic") {
            self.userMnemonics = updated
        }
    }

    private func deleteMnemonic(_ entry: DatabaseService.UserContent) async {
        guard let db = appState.databaseService else { return }
        try? db.deleteUserContent(id: entry.id)
        await reloadUserMnemonics()
    }
}

// MARK: - Mnemonic Editor (sheet)
//
// Reused for both add (existing == nil) and edit. Saves on Cmd+Return or
// the Save button; cancel discards. Multiline text input.

private struct MnemonicEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let wordId: String
    let existing: DatabaseService.UserContent?
    let onSave: (DatabaseService.UserContent) -> Void

    @State private var text: String = ""
    @State private var isSaving: Bool = false
    @FocusState private var fieldFocused: Bool

    private var isEditing: Bool { existing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit mnemonic" : "Add a mnemonic")
                .font(.headline)

            Text("Tip: Use word roots, sound associations, or vivid images. Anything that helps you recall.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .focused($fieldFocused)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Update" : "Save") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            text = existing?.content ?? ""
            fieldFocused = true
        }
    }

    private func save() async {
        guard let db = appState.databaseService else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if let existing {
                try db.updateUserContent(id: existing.id, content: trimmed)
                let updated = DatabaseService.UserContent(
                    id: existing.id,
                    wordId: existing.wordId,
                    type: existing.type,
                    content: trimmed,
                    createdAt: existing.createdAt,
                    updatedAt: Date()
                )
                onSave(updated)
            } else {
                let id = try db.addUserContent(wordId: wordId, type: "mnemonic", content: trimmed)
                let created = DatabaseService.UserContent(
                    id: id,
                    wordId: wordId,
                    type: "mnemonic",
                    content: trimmed,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                onSave(created)
            }
            dismiss()
        } catch {
            print("Failed to save mnemonic: \(error)")
        }
    }
}

// MARK: - Simple flow-wrap HStack
//
// Apple's Layout protocol gives us this in 4 lines; used for chips that
// wrap onto multiple rows.

private struct FlowHStack: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let p = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var maxX: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, s.height)
            x += s.width + spacing
            maxX = max(maxX, x)
        }
        return (CGSize(width: maxX, height: y + rowH), positions)
    }
}
