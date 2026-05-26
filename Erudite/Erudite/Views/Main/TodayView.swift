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

            // Quick stats
            HStack(spacing: 32) {
                StatBadge(title: "Total Words", value: "\(appState.wordCount)", icon: "character.book.closed", color: .purple)
                StatBadge(title: "Due Today", value: "\(appState.dueCount)", icon: "arrow.clockwise", color: .orange)
                StatBadge(title: "New", value: "\(appState.newCount)", icon: "plus.circle", color: .blue)
            }

            // Quick actions
            HStack(spacing: 16) {
                ActionButton(title: "Start Learning", icon: "book", color: .blue) {
                    appState.startStudy(mode: .mixed)
                }
                ActionButton(title: "Review Due", icon: "arrow.clockwise", color: .green) {
                    appState.startStudy(mode: .reviewOnly)
                }
                ActionButton(title: "New Words", icon: "plus.circle", color: .orange) {
                    appState.startStudy(mode: .newOnly)
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
