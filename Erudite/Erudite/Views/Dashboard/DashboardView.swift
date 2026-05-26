import SwiftUI
import Charts

// MARK: - Dashboard View (Statistics)

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var overview: StatisticsEngine.OverviewStats?
    @State private var dailyActivity: [DailyActivity] = []
    @State private var ratingDistribution: [RatingCount] = []

    private let engine = StatisticsEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("Statistics")
                        .font(.title)
                        .fontWeight(.bold)
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await loadStats() }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)

                if let stats = overview {
                    // Overview cards
                    overviewGrid(stats)

                    // Activity chart
                    if !dailyActivity.isEmpty {
                        activityChart
                    }

                    // Rating breakdown
                    if !ratingDistribution.isEmpty {
                        ratingChart
                    }

                    // Progress breakdown
                    progressBreakdown(stats)
                } else {
                    ContentUnavailableView(
                        "No Data Yet",
                        systemImage: "chart.bar",
                        description: Text("Start studying to see your statistics here.")
                    )
                }

                Spacer()
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadStats() }
    }

    // MARK: - Overview Grid

    private func overviewGrid(_ stats: StatisticsEngine.OverviewStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 16) {
            DashboardCard(title: "Mastered", value: "\(stats.mastered)", subtitle: "words", color: .green)
            DashboardCard(title: "Learning", value: "\(stats.learning)", subtitle: "in progress", color: .blue)
            DashboardCard(title: "Retention", value: stats.retentionRate > 0 ? "\(Int(stats.retentionRate * 100))%" : "—", subtitle: "accuracy", color: .purple)
            DashboardCard(title: "Streak", value: "\(stats.currentStreak)", subtitle: stats.currentStreak == 1 ? "day" : "days", color: .orange)
        }
        .padding(.horizontal)
    }

    // MARK: - Activity Chart (last 14 days)

    private var activityChart: some View {
        GroupBox("Daily Activity (Last 14 Days)") {
            Chart(dailyActivity) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Cards", day.count)
                )
                .foregroundStyle(day.isToday ? Color.blue : Color.blue.opacity(0.6))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
            .padding(.top, 8)
        }
        .padding(.horizontal)
    }

    // MARK: - Rating Chart

    private var ratingChart: some View {
        GroupBox("Rating Distribution") {
            Chart(ratingDistribution) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(item.color)
                .annotation(position: .overlay) {
                    if item.count > 0 {
                        Text("\(item.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 160)
            .padding(.top, 8)

            // Legend
            HStack(spacing: 16) {
                ForEach(ratingDistribution) { item in
                    HStack(spacing: 4) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text("\(item.label) (\(item.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    // MARK: - Progress Breakdown

    private func progressBreakdown(_ stats: StatisticsEngine.OverviewStats) -> some View {
        GroupBox("Vocabulary Progress") {
            VStack(spacing: 12) {
                progressRow(label: "Mastered", count: stats.mastered, total: stats.totalWords, color: .green)
                progressRow(label: "Learning", count: stats.learning, total: stats.totalWords, color: .blue)
                progressRow(label: "New", count: stats.newRemaining, total: stats.totalWords, color: .secondary)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal)
    }

    private func progressRow(label: String, count: Int, total: Int, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                let fraction = total > 0 ? CGFloat(count) / CGFloat(total) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Data Loading

    private func loadStats() async {
        guard let db = appState.databaseService else { return }
        do {
            let cards = try db.fetchAllCards()
            let logs = try db.fetchAllReviewLogs()

            overview = engine.computeOverview(cards: cards, logs: logs)

            // Daily activity (last 14 days)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            dailyActivity = (0..<14).reversed().map { daysAgo in
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
                let nextDate = calendar.date(byAdding: .day, value: 1, to: date)!
                let count = logs.filter { $0.timestamp >= date && $0.timestamp < nextDate }.count
                return DailyActivity(date: date, count: count, isToday: daysAgo == 0)
            }

            // Rating distribution
            let ratingCounts = Dictionary(grouping: logs, by: { $0.rating })
            ratingDistribution = Rating.allCases.map { rating in
                RatingCount(
                    rating: rating,
                    count: ratingCounts[rating]?.count ?? 0
                )
            }
        } catch {
            print("Failed to load stats: \(error)")
        }
    }
}

// MARK: - Data Models

private struct DailyActivity: Identifiable {
    let date: Date
    let count: Int
    let isToday: Bool
    var id: Date { date }
}

private struct RatingCount: Identifiable {
    let rating: Rating
    let count: Int
    var id: Rating { rating }

    var label: String { rating.label }
    var color: Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .mint
        }
    }
}

// MARK: - Dashboard Card

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
