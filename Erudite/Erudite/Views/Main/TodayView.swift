import SwiftUI

// MARK: - Today View (Home / Daily Briefing)

struct TodayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Good \(greetingTime)!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(Date(), style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            // Word Book Picker
            if !appState.wordBooks.isEmpty {
                bookPicker
            }

            // Quick stats
            HStack(spacing: 32) {
                StatBadge(title: "Learned", value: "\(appState.learnedCount)", icon: "checkmark.circle", color: .green)
                StatBadge(title: "Due", value: "\(appState.dueCount)", icon: "arrow.clockwise", color: .orange)
                StatBadge(title: "Remaining", value: "\(appState.newCount)", icon: "plus.circle", color: .blue)
            }

            // Progress bar (for active book)
            if let book = appState.activeBook {
                bookProgress(book: book)
            }

            // Quick actions
            HStack(spacing: 16) {
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

            // Status card
            if appState.dueCount == 0 && appState.isDBReady {
                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All caught up!")
                                .font(.headline)
                            Text("No reviews due. Start learning new words or come back later.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }
                .frame(maxWidth: 450)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            appState.refreshStats()
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
        @Bindable var state = appState
        return HStack(spacing: 12) {
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
            .frame(maxWidth: 300)
        }
        .padding(.horizontal)
    }

    private func bookProgress(book: WordBook) -> some View {
        let total = book.wordCount
        let learned = appState.learnedCount
        let fraction = total > 0 ? Double(learned) / Double(total) : 0

        return VStack(spacing: 6) {
            HStack {
                Text("\(book.name)")
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
        .frame(maxWidth: 400)
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

private struct StatBadge: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 100)
    }
}

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
