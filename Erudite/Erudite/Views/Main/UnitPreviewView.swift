import SwiftUI

// MARK: - Unit Preview View
//
// Shown as a sheet after the user taps a unit on Today (or Plan / Library
// "study this chapter"). The intent is the GRE-3000 paper-book experience:
//
//   1. See the title (Reviews · 1 / GRE 3000 · Unit 5)
//   2. Scan the 12 words for ~30 seconds — spelling + Chinese gloss
//   3. Pick a study mode (Flashcard for FSRS-driven recall, Typing for
//      spelling drill) and dive in
//
// Both buttons launch into the same StudyUnit (cards prefetched), so
// switching mode mid-session is just "back to preview, pick the other one".
//
// Esc dismisses the sheet without committing — the user can browse units
// without locking themselves into one.

struct UnitPreviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let unit: StudyUnit

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            wordList
            Divider()
            actions
        }
        .frame(minWidth: 480, minHeight: 520)
        .background(
            // Esc closes — same idiom as the popover. Hidden Button is
            // focus-independent.
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: unit.kind.icon)
                    .foregroundStyle(color(for: unit.kind.color))
                    .font(.title3)
                Text(unit.title)
                    .font(.title2.weight(.bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            Text(unit.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Take 30 seconds to scan these — context primes recall.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding()
    }

    // MARK: - Word List

    private var wordList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(unit.orderedWords.enumerated()), id: \.element.id) { idx, word in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(word.spelling)
                                    .font(.system(.body, design: .serif).weight(.semibold))
                                if let p = word.phonetic, !p.isEmpty {
                                    Text(p)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let def = word.definitions.first {
                                HStack(spacing: 4) {
                                    if !def.partOfSpeech.isEmpty {
                                        Text(def.partOfSpeech)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                                    }
                                    Text(def.chinese)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .frame(width: 80)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                appState.startUnit(unit, in: .typing)
                dismiss()
            } label: {
                Label("Typing", systemImage: "keyboard")
                    .frame(width: 110)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                appState.startUnit(unit, in: .flashcard)
                dismiss()
            } label: {
                Label("Flashcard", systemImage: "rectangle.on.rectangle")
                    .frame(width: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Helpers

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
