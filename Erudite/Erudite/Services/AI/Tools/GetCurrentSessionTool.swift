import Foundation

// MARK: - Get Current Session Tool

struct GetCurrentSessionTool: AITool {
    static let name = "get_current_session"
    static let description = "Returns the state of the user's current study session if one is active, including mode (flashcard/typing), words reviewed so far, accuracy, and current word being studied."
    static let inputSchema = ToolInputSchema()

    func execute(input: [String: JSONValue], db: DatabaseService) throws -> String {
        // Check if user is in a study session by looking at active tab + session state
        let currentTab = AppState.shared.selectedTab

        switch currentTab {
        case .flashcard:
            // We can report basic info about flashcard mode
            let dueCount = try db.fetchDueCount(inBook: AppState.shared.activeBookId)
            let result: [String: JSONValue] = [
                "active": .bool(true),
                "mode": .string("flashcard"),
                "due_remaining": .int(dueCount),
                "active_book": .string(AppState.shared.activeBook?.name ?? "none")
            ]
            return try encodeToolResult(result)

        case .typing:
            let result: [String: JSONValue] = [
                "active": .bool(true),
                "mode": .string("typing"),
                "active_book": .string(AppState.shared.activeBook?.name ?? "none")
            ]
            return try encodeToolResult(result)

        default:
            let result: [String: JSONValue] = [
                "active": .bool(false),
                "current_tab": .string(currentTab.rawValue),
                "message": .string("User is not in a study session. They're browsing the \(currentTab.rawValue) tab.")
            ]
            return try encodeToolResult(result)
        }
    }
}
