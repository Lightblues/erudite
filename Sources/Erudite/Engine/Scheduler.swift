import Foundation

// MARK: - Scheduler
// Determines which cards to study in a session (due reviews + new cards)

final class Scheduler {
    private let parameters: FSRSParameters

    init(parameters: FSRSParameters = .default) {
        self.parameters = parameters
    }

    struct DailyPlan {
        let dueReviews: [ReviewCard]
        let newCards: [ReviewCard]
        let estimatedMinutes: Int

        var totalCount: Int { dueReviews.count + newCards.count }
    }

    /// Generate today's study plan from all cards
    func planForToday(allCards: [ReviewCard], now: Date = Date()) -> DailyPlan {
        let due = allCards
            .filter { $0.state != .new && $0.dueDate <= now }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(parameters.dailyReviewLimit)

        let new = allCards
            .filter { $0.state == .new }
            .prefix(parameters.dailyNewLimit)

        let total = due.count + new.count
        let estimatedMinutes = max(1, total / 3) // rough: ~3 cards per minute

        return DailyPlan(
            dueReviews: Array(due),
            newCards: Array(new),
            estimatedMinutes: estimatedMinutes
        )
    }
}
