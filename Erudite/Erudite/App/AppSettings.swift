import Foundation

// MARK: - AppSettings
//
// Process-wide knobs that aren't tied to a specific tab. UnitSize is the
// canonical "how many cards in a chunk" — used by Flashcard's session
// chunking AND by Book Chapter sizing AND by Today's review-slicing.
// One source of truth so they don't drift.
//
// Persistence: UserDefaults with stable keys. New settings should default
// to safe values and document why.

@MainActor
@Observable
final class AppSettings {
    /// Cards per study unit (Flashcard chunk, Book Chapter size, Today
    /// review slice). 12 is the empirical sweet spot for ~5-7 minute
    /// chunks; range 8–20 covers user preference reasonably.
    var unitSize: Int {
        didSet { UserDefaults.standard.set(unitSize, forKey: Self.unitSizeKey) }
    }
    static let unitSizeKey = "study.unitSize"
    static let unitSizeMin = 5
    static let unitSizeMax = 30
    static let unitSizeDefault = 12

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.unitSizeKey)
        let initial = stored == 0 ? Self.unitSizeDefault : stored
        self.unitSize = min(max(initial, Self.unitSizeMin), Self.unitSizeMax)
    }
}
