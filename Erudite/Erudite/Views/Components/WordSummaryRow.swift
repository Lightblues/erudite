import SwiftUI

// MARK: - WordSummaryRow
//
// Shared row used by Library, Today preview, and Plan tab. Renders the
// lightweight WordSummary projection without ever needing the full Word.
//
// Two density modes: .standard for full-width Library rows, .compact for
// the narrower two-column Today preview where vertical space matters.
//
// The previous "tier badge" (C/M/A circle) was removed in 2026-05 — the
// underlying frequency tier had no authoritative GRE provenance and the
// distribution was so skewed (80% in advanced) that it added clutter
// without information. WordSummary.frequency is still kept on the model
// for backward compat / possible future re-introduction with a real signal.

struct WordSummaryRow: View {
    let summary: WordSummary
    var density: Density = .standard
    var showStateBadge: Bool = true
    var trailingText: String? = nil   // explicit override (e.g. "today", "1d late")
    /// When provided and `trailingText` is nil, the row auto-picks a
    /// trailing label appropriate to the sort: due date for `.dueDate`,
    /// "L:N" for `.lapses`. Lets list views show *why* a row is where it is.
    var trailingForSort: WordSort? = nil

    enum Density {
        case standard
        case compact
    }

    var body: some View {
        HStack(spacing: density == .compact ? 8 : 12) {
            VStack(alignment: .leading, spacing: density == .compact ? 1 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(summary.spelling)
                        .font(density == .compact ? .subheadline.weight(.semibold) : .headline)
                    if density == .standard, let phonetic = summary.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if summary.firstDefZh != nil || summary.posLabel != nil {
                    HStack(spacing: 4) {
                        if let pos = summary.posLabel, !pos.isEmpty {
                            Text(pos)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                        }
                        if let def = summary.firstDefZh, !def.isEmpty {
                            Text(def)
                                .font(density == .compact ? .caption : .subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            if let label = resolvedTrailing {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if summary.hasUserMnemonic {
                // Purple lightbulb = user has authored their own mnemonic
                // for this word. After v3.0, builtin mnemonics are universal
                // (~100% coverage) so they no longer have signal value as a
                // list indicator — flip the icon to mean "this is one I've
                // annotated myself" instead.
                Image(systemName: "lightbulb.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .help("You've added a personal mnemonic")
            }

            if showStateBadge {
                stateBadge
            }
        }
        .padding(.vertical, density == .compact ? 2 : 4)
    }

    private var resolvedTrailing: String? {
        if let trailingText { return trailingText }
        guard let sort = trailingForSort else { return nil }
        switch sort {
        case .bookOrder, .alphabetical:
            return nil
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private var stateBadge: some View {
        let resolvedState = summary.cardState ?? .new
        let (color, label): (Color, String) = switch resolvedState {
        case .new: (.gray, "New")
        case .learning: (.orange, "Learning")
        case .review: (.green, "Review")
        case .relearning: (.red, "Relearn")
        }
        Text(label)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Relative due-date helpers (used by Today + Plan)

enum DueDateFormatter {
    /// Returns a short relative label like "today", "2d late", "tomorrow", "in 3d".
    /// Always uses local-day boundaries so a card due at 23:59 today shows "today",
    /// not "1d late" at 00:01.
    static func relativeLabel(for due: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: due)
        let nowDay = cal.startOfDay(for: now)
        let days = cal.dateComponents([.day], from: nowDay, to: dueDay).day ?? 0
        switch days {
        case ..<(-1): return "\(-days)d late"
        case -1: return "1d late"
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days)d"
        }
    }
}
