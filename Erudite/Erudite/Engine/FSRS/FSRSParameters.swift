import Foundation

// MARK: - FSRS Parameters (Placeholder)
// FSRS-5 has 19 trainable parameters. These are defaults from the reference implementation.
// Future: allow per-user optimization based on review history.

struct FSRSParameters {
    // Initial stability for each rating when card is new
    let initialStability: [Rating: Double] = [
        .again: 0.4,
        .hard: 0.9,
        .good: 2.3,
        .easy: 5.0
    ]

    // Initial difficulty for each rating
    let initialDifficulty: [Rating: Double] = [
        .again: 7.0,
        .hard: 6.0,
        .good: 5.0,
        .easy: 3.0
    ]

    // Desired retention rate (default 90%)
    var desiredRetention: Double = 0.9

    // Maximum interval in days
    var maximumInterval: Int = 365

    // Daily limits
    var dailyNewLimit: Int = 10
    var dailyReviewLimit: Int = 200

    static let `default` = FSRSParameters()
}
