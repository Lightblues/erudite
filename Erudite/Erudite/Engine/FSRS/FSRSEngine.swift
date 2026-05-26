import Foundation

// MARK: - FSRS Engine (Stub Implementation)
// Full algorithm implementation in a future issue.
// This stub returns fixed intervals to allow UI development.

@MainActor
final class FSRSEngine {

    // MARK: - Scheduling Result

    struct SchedulingResult {
        let again: ReviewCard
        let hard: ReviewCard
        let good: ReviewCard
        let easy: ReviewCard

        /// Human-readable intervals for display
        let againInterval: String
        let hardInterval: String
        let goodInterval: String
        let easyInterval: String
    }

    // MARK: - Public API

    /// Schedule the next review for a card based on each possible rating.
    /// Currently returns stub intervals; will implement FSRS-5 algorithm later.
    func schedule(card: ReviewCard, now: Date = Date()) -> SchedulingResult {
        switch card.state {
        case .new:
            return scheduleNew(card: card, now: now)
        case .learning, .relearning:
            return scheduleLearning(card: card, now: now)
        case .review:
            return scheduleReview(card: card, now: now)
        }
    }

    // MARK: - Stub Implementations

    private func scheduleNew(card: ReviewCard, now: Date) -> SchedulingResult {
        SchedulingResult(
            again: card.updated(state: .learning, stability: 0.5, scheduledDays: 0, dueDate: now.addingMinutes(1)),
            hard: card.updated(state: .learning, stability: 1.0, scheduledDays: 0, dueDate: now.addingMinutes(6)),
            good: card.updated(state: .learning, stability: 2.0, scheduledDays: 0, dueDate: now.addingMinutes(10)),
            easy: card.updated(state: .review, stability: 4.0, scheduledDays: 4, dueDate: now.addingDays(4)),
            againInterval: "<1m",
            hardInterval: "6m",
            goodInterval: "10m",
            easyInterval: "4d"
        )
    }

    private func scheduleLearning(card: ReviewCard, now: Date) -> SchedulingResult {
        SchedulingResult(
            again: card.updated(state: .relearning, stability: 0.5, scheduledDays: 0, dueDate: now.addingMinutes(5)),
            hard: card.updated(state: .learning, stability: 1.5, scheduledDays: 0, dueDate: now.addingMinutes(10)),
            good: card.updated(state: .review, stability: 3.0, scheduledDays: 1, dueDate: now.addingDays(1)),
            easy: card.updated(state: .review, stability: 7.0, scheduledDays: 4, dueDate: now.addingDays(4)),
            againInterval: "5m",
            hardInterval: "10m",
            goodInterval: "1d",
            easyInterval: "4d"
        )
    }

    private func scheduleReview(card: ReviewCard, now: Date) -> SchedulingResult {
        let baseInterval = max(1, card.scheduledDays)
        return SchedulingResult(
            again: card.updated(state: .relearning, stability: card.stability * 0.5, scheduledDays: 0, dueDate: now.addingMinutes(10), lapses: card.lapses + 1),
            hard: card.updated(state: .review, stability: card.stability * 1.2, scheduledDays: Int(Double(baseInterval) * 1.2), dueDate: now.addingDays(Int(Double(baseInterval) * 1.2))),
            good: card.updated(state: .review, stability: card.stability * 2.5, scheduledDays: Int(Double(baseInterval) * 2.5), dueDate: now.addingDays(Int(Double(baseInterval) * 2.5))),
            easy: card.updated(state: .review, stability: card.stability * 3.5, scheduledDays: Int(Double(baseInterval) * 3.5), dueDate: now.addingDays(Int(Double(baseInterval) * 3.5))),
            againInterval: "10m",
            hardInterval: "\(Int(Double(baseInterval) * 1.2))d",
            goodInterval: "\(Int(Double(baseInterval) * 2.5))d",
            easyInterval: "\(Int(Double(baseInterval) * 3.5))d"
        )
    }
}

// MARK: - ReviewCard Helpers

private extension ReviewCard {
    func updated(
        state: CardState? = nil,
        stability: Double? = nil,
        scheduledDays: Int? = nil,
        dueDate: Date? = nil,
        lapses: Int? = nil
    ) -> ReviewCard {
        var copy = self
        if let state { copy.state = state }
        if let stability { copy.stability = stability }
        if let scheduledDays { copy.scheduledDays = scheduledDays }
        if let dueDate { copy.dueDate = dueDate }
        if let lapses { copy.lapses = lapses }
        copy.reps += 1
        copy.lastReview = Date()
        return copy
    }
}

// MARK: - Date Helpers

private extension Date {
    func addingMinutes(_ minutes: Int) -> Date {
        addingTimeInterval(TimeInterval(minutes * 60))
    }

    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}
