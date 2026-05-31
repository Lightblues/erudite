import SwiftUI

// MARK: - SessionSummaryView
//
// Unified post-session summary used by:
// - Flashcard `.complete` and `.unitComplete`
// - Typing `.chapterComplete`
//
// Renders a fixed shape: header (mode + unit title), stat strip, mini-grid
// of words with rating-color, action row. Mode-specific extras (WPM)
// surface conditionally so each call site can pass the same struct.
//
// Action callbacks let the caller decide what "Continue" / "Done" do
// (continue to next unit / dismiss / back to Today).

struct SessionSummaryView: View {
    let result: SessionResult
    /// Header line above the title. Use for "Unit complete" vs
    /// "Session complete" vs "Chapter complete".
    var heading: String = "Session complete"
    /// Primary button (default action). Pass nil to omit.
    var primaryAction: Action?
    /// Secondary button. Pass nil to omit.
    var secondaryAction: Action?

    struct Action {
        let label: String
        let systemImage: String?
        let role: ButtonRole?
        let perform: () -> Void

        init(_ label: String, systemImage: String? = nil, role: ButtonRole? = nil, perform: @escaping () -> Void) {
            self.label = label
            self.systemImage = systemImage
            self.role = role
            self.perform = perform
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                statStrip

                if !result.entries.isEmpty {
                    wordsGrid
                }

                actions

                Text(keyboardHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text(heading)
                .font(.title2.weight(.bold))
            if let unit = result.unit {
                Text(unit.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stat strip

    private var statStrip: some View {
        HStack(spacing: 28) {
            stat(value: "\(result.totalCards)", label: "Cards", color: .blue)
            stat(value: formatDuration(result.durationSeconds), label: "Time", color: .purple)
            stat(value: "\(Int(result.accuracy * 100))%", label: "Accuracy",
                 color: result.accuracy >= 0.8 ? .green : .orange)
            stat(value: "\(result.againCount)", label: "Again",
                 color: result.againCount == 0 ? .secondary : .red)
            if let wpm = result.wpm, wpm > 0 {
                stat(value: String(format: "%.0f", wpm), label: "WPM", color: .indigo)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func stat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Words grid

    private var wordsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(result.sortedEntries, id: \.word.id) { entry in
                Text(entry.word.spelling)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(entryColor(entry).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(entryColor(entry))
                    .help(entryTooltip(entry))
            }
        }
        .frame(maxWidth: 560)
    }

    private func entryColor(_ entry: SessionResult.Entry) -> Color {
        if let r = entry.rating { return ratingColor(r) }
        // Typing-only
        if entry.mistakes >= 3 { return .red }
        if entry.mistakes > 0 { return .orange }
        return .green
    }

    private func entryTooltip(_ entry: SessionResult.Entry) -> String {
        var bits: [String] = []
        if let r = entry.rating { bits.append("rating: \(r.label)") }
        if entry.mistakes > 0 { bits.append("\(entry.mistakes) mistakes") }
        if entry.attempts > 1 { bits.append("\(entry.attempts) attempts") }
        return bits.joined(separator: " · ")
    }

    private func ratingColor(_ rating: Rating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            if let secondary = secondaryAction {
                Button(role: secondary.role, action: secondary.perform) {
                    actionLabel(secondary).frame(width: 110)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if let primary = primaryAction {
                Button(role: primary.role, action: primary.perform) {
                    actionLabel(primary).frame(width: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private func actionLabel(_ action: Action) -> some View {
        if let img = action.systemImage {
            Label(action.label, systemImage: img)
        } else {
            Text(action.label)
        }
    }

    // MARK: - Helpers

    private var keyboardHint: String {
        switch (primaryAction, secondaryAction) {
        case (nil, nil): return ""
        case (.some, nil): return "Return / Space to confirm"
        case (.some, .some): return "Return for primary · Esc to cancel"
        case (nil, .some): return "Esc to dismiss"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
