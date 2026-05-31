import SwiftUI

// MARK: - UnitPickerView
//
// Shared "list of StudyUnits the user can pick from" component. Used by:
//
// - Today, as the "Today's homework" section.
// - Empty Flashcard/Typing state, when the user lands on the tab without
//   a pinned `currentUnit` — instead of a dead "no session" screen, they
//   see the same picker and can dive in directly.
//
// Pure rendering: takes the units in, calls back when one is picked.
// Owns no state. The receiving view decides what to do with the pick
// (open UnitPreview as a sheet, or pin + switch tab).

struct UnitPickerView: View {
    let units: [StudyUnit]
    let onPick: (StudyUnit) -> Void

    /// Optional header shown above the list. nil = no header.
    var header: String? = "Today's homework"

    /// Optional summary line ("4 units · ~22 min"). nil = derived from units.
    var subtitle: String? = nil

    /// Optional empty-state title shown when units is empty.
    var emptyTitle: String = "All caught up"
    var emptyMessage: String = "No reviews due. New words will appear when the queue refreshes."

    var body: some View {
        if units.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let header {
                    HStack {
                        Text(header)
                            .font(.headline)
                        Spacer()
                        Text(subtitle ?? defaultSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 6) {
                    ForEach(units) { unit in
                        unitRow(unit)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text(emptyTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    /// "4 units · ~22 min" / "1 unit · ~5 min"
    private var defaultSubtitle: String {
        let total = units.count
        let minutes = units.reduce(0) { $0 + $1.estimatedMinutes }
        return "\(total) unit\(total == 1 ? "" : "s") · ~\(minutes) min"
    }

    private func unitRow(_ unit: StudyUnit) -> some View {
        Button {
            onPick(unit)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: unit.kind.icon)
                    .foregroundStyle(color(for: unit.kind.color))
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.title)
                        .font(.subheadline.weight(.semibold))
                    Text(unit.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.quaternary, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func color(for name: StudyUnit.ColorName) -> Color {
        switch name {
        case .orange: .orange
        case .blue: .blue
        case .purple: .purple
        case .indigo: .indigo
        case .pink: .pink
        }
    }
}
