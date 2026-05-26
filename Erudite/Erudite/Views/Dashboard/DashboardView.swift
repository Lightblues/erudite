import SwiftUI

// MARK: - Dashboard View (Statistics)

struct DashboardView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Statistics")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            // Stats grid placeholder
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 16) {
                DashboardCard(title: "Mastered", value: "—", subtitle: "words", color: .green)
                DashboardCard(title: "Learning", value: "—", subtitle: "in progress", color: .blue)
                DashboardCard(title: "Retention", value: "—%", subtitle: "avg rate", color: .purple)
            }
            .padding(.horizontal)

            // Chart placeholder
            GroupBox("Retention Curve") {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 200)
                    .overlay {
                        Text("Swift Charts will render here")
                            .foregroundStyle(.secondary)
                    }
            }
            .padding(.horizontal)

            // Heatmap placeholder
            GroupBox("Study Streak") {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 120)
                    .overlay {
                        Text("Heatmap calendar will render here")
                            .foregroundStyle(.secondary)
                    }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DashboardCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
