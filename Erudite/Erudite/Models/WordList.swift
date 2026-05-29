import Foundation

// MARK: - WordBook

nonisolated struct WordBook: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let exam: String?             // "GRE", "TOEFL", "SAT"
    let description: String?
    let source: String?
    let wordCount: Int
    let structure: String         // "sequential" | "thematic" | "frequency"
    let isBuiltin: Bool
    let createdAt: Date

    init(
        id: String,
        name: String,
        exam: String? = nil,
        description: String? = nil,
        source: String? = nil,
        wordCount: Int = 0,
        structure: String = "sequential",
        isBuiltin: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.exam = exam
        self.description = description
        self.source = source
        self.wordCount = wordCount
        self.structure = structure
        self.isBuiltin = isBuiltin
        self.createdAt = createdAt
    }
}
