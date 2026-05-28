import Foundation

// MARK: - AI Tool Protocol

/// A tool the AI agent can invoke to query or mutate learning state.
protocol AITool {
    /// Unique tool name matching the API tool definition
    static var name: String { get }

    /// Human-readable description for the model
    static var description: String { get }

    /// JSON Schema for the input parameters
    static var inputSchema: ToolInputSchema { get }

    /// Execute the tool with the given input.
    /// Returns a JSON string result for the tool_result content block.
    func execute(input: [String: JSONValue], db: DatabaseService) throws -> String
}

// MARK: - Tool Registry

/// Singleton registry that maps tool names to implementations.
final class ToolRegistry {
    static let shared = ToolRegistry()

    private var tools: [String: any AITool] = [:]

    private init() {
        register(GetUserStatsTool())
        register(GetWordHistoryTool())
        register(GetWeakWordsTool())
        register(GetCurrentSessionTool())
    }

    private func register(_ tool: any AITool) {
        tools[type(of: tool).name] = tool
    }

    /// All tool definitions for the API request
    var definitions: [ToolDefinition] {
        tools.values.map { tool in
            ToolDefinition(
                name: type(of: tool).name,
                description: type(of: tool).description,
                input_schema: type(of: tool).inputSchema
            )
        }
    }

    /// Execute a tool by name.
    func execute(name: String, input: [String: JSONValue], db: DatabaseService) throws -> String {
        guard let tool = tools[name] else {
            throw ToolError.unknownTool(name)
        }
        return try tool.execute(input: input, db: db)
    }
}

// MARK: - Tool Errors

enum ToolError: LocalizedError {
    case unknownTool(String)
    case invalidInput(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "Unknown tool: \(name)"
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        case .executionFailed(let msg): return "Tool execution failed: \(msg)"
        }
    }
}

// MARK: - JSON Encoding Helper

/// Encode a dictionary to a JSON string for tool results.
func encodeToolResult(_ value: [String: JSONValue]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? "{}"
}
