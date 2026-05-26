import Foundation

// MARK: - Statistics Engine
// Aggregates review data for dashboard display

final class StatisticsEngine {

    struct DailyStats {
        let date: Date
        let newLearned: Int
        let reviewed: Int
        let accuracy: Double // 0.0 - 1.0
        let timeSpentMinutes: Int
    }

    struct OverviewStats {
        let totalWords: Int
        let mastered: Int       // state == .review && stability > 21
        let learning: Int       // state == .learning || .relearning
        let newRemaining: Int   // state == .new
        let currentStreak: Int  // consecutive days with study
        let retentionRate: Double
    }

    /// Compute overview stats from current card states and logs
    func computeOverview(cards: [ReviewCard], logs: [ReviewLog]) -> OverviewStats {
        let mastered = cards.filter { $0.state == .review && $0.stability > 21 }.count
        let learning = cards.filter { $0.state == .learning || $0.state == .relearning }.count
        let newRemaining = cards.filter { $0.state == .new }.count

        let totalRatings = logs.count
        let goodOrBetter = logs.filter { $0.rating.rawValue >= Rating.good.rawValue }.count
        let retention = totalRatings > 0 ? Double(goodOrBetter) / Double(totalRatings) : 0.0

        return OverviewStats(
            totalWords: cards.count,
            mastered: mastered,
            learning: learning,
            newRemaining: newRemaining,
            currentStreak: computeStreak(logs: logs),
            retentionRate: retention
        )
    }

    private func computeStreak(logs: [ReviewLog]) -> Int {
        guard !logs.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var streak = 0
        var checkDate = today

        let logDates = Set(logs.map { calendar.startOfDay(for: $0.timestamp) })

        while logDates.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }
}
