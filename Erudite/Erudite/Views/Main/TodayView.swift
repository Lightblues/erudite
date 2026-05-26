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

            // AI Briefing placeholder
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Daily Briefing", systemImage: "sparkles")
                        .font(.headline)

                    Text("AI briefing will appear here once connected.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxWidth: 500)

            // Quick stats placeholder
            HStack(spacing: 32) {
                StatBadge(title: "Due Today", value: "—", icon: "arrow.clockwise")
                StatBadge(title: "New Words", value: "—", icon: "plus.circle")
                StatBadge(title: "Streak", value: "—", icon: "flame")
            }

            // Quick actions
            HStack(spacing: 16) {
                ActionButton(title: "Start Learning", icon: "book", color: .blue)
                ActionButton(title: "Quick Review", icon: "rectangle.on.rectangle", color: .green)
                ActionButton(title: "Practice Quiz", icon: "questionmark.circle", color: .orange)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
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

    var body: some View {
        Button {
            // TODO: navigate to respective view
        } label: {
            Label(title, systemImage: icon)
                .frame(width: 140)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .controlSize(.large)
    }
}
