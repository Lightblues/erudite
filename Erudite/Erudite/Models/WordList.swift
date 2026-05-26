import Foundation

// MARK: - WordList

struct WordList: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    let isBuiltin: Bool
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        isBuiltin: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isBuiltin = isBuiltin
        self.createdAt = createdAt
    }
}
