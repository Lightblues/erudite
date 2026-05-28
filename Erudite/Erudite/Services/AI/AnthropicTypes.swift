import Foundation

// MARK: - Anthropic Messages API Types

// MARK: Request

struct AnthropicRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: [SystemBlock]?
    let messages: [APIMessage]
    let tools: [ToolDefinition]?
    let stream: Bool

    struct SystemBlock: Encodable {
        let type: String
        let text: String
        let cache_control: CacheControl?

        init(text: String, cacheControl: Bool = false) {
            self.type = "text"
            self.text = text
            self.cache_control = cacheControl ? CacheControl(type: "ephemeral") : nil
        }
    }

    struct CacheControl: Encodable {
        let type: String
    }
}

// MARK: - Model Constants

enum AnthropicModel {
    static let sonnet = "claude-sonnet-4-20250514"
    static let haiku = "claude-haiku-4-20250414"
}

// MARK: - API Message (wire format)

struct APIMessage: Codable {
    let role: MessageRole
    let content: [ContentBlock]
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

// MARK: - Content Block

enum ContentBlock: Codable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: String, isError: Bool)

    // MARK: Encodable

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .tool_use_id)
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(true, forKey: .is_error)
            }
        }
    }

    // MARK: Decodable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(JSONValue.self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .tool_use_id)
            let content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
            let isError = try container.decodeIfPresent(Bool.self, forKey: .is_error) ?? false
            self = .toolResult(toolUseId: toolUseId, content: content, isError: isError)
        default:
            // Unknown block type — treat as text with a note
            self = .text("[Unknown content block type: \(type)]")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case tool_use_id, content, is_error
    }
}

// MARK: - Tool Definition

struct ToolDefinition: Encodable {
    let name: String
    let description: String
    let input_schema: ToolInputSchema
}

struct ToolInputSchema: Encodable {
    let type: String
    let properties: [String: ToolProperty]?
    let required: [String]?

    init(properties: [String: ToolProperty]? = nil, required: [String]? = nil) {
        self.type = "object"
        self.properties = properties
        self.required = required
    }
}

struct ToolProperty: Encodable {
    let type: String
    let description: String?
    let enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }

    init(type: String, description: String? = nil, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
}

// MARK: - Non-Streaming Response (for reference / future use)

struct AnthropicResponse: Decodable {
    let id: String
    let model: String
    let content: [ContentBlock]
    let stop_reason: String?
    let usage: Usage?
}

// MARK: - SSE Stream Event Types

enum StreamEvent {
    case messageStart(MessageStartPayload)
    case contentBlockStart(index: Int, contentBlock: ContentBlockInfo)
    case contentBlockDelta(index: Int, delta: ContentDelta)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?, usage: Usage?)
    case messageStop
    case ping
    case error(APIError)
}

struct MessageStartPayload: Decodable {
    let message: MessageInfo

    struct MessageInfo: Decodable {
        let id: String
        let model: String
        let usage: Usage?
    }
}

struct ContentBlockInfo: Decodable {
    let type: String       // "text" or "tool_use"
    let id: String?        // present for tool_use
    let name: String?      // present for tool_use
}

enum ContentDelta {
    case textDelta(String)
    case inputJSONDelta(String)
}

struct Usage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}

struct APIError: Decodable, Error, LocalizedError {
    let type: String
    let message: String

    var errorDescription: String? { message }
}

// MARK: - JSONValue (arbitrary JSON)

enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Decodable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode JSONValue")
            )
        }
    }

    // MARK: Encodable

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    // MARK: Convenience accessors

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }
}

// MARK: - SSE JSON Decode Helpers (internal wrappers)

struct SSEContentBlockStartPayload: Decodable {
    let index: Int
    let content_block: ContentBlockInfo
}

struct SSEContentBlockDeltaPayload: Decodable {
    let index: Int
    let delta: DeltaInfo

    struct DeltaInfo: Decodable {
        let type: String
        let text: String?
        let partial_json: String?
    }
}

struct SSEContentBlockStopPayload: Decodable {
    let index: Int
}

struct SSEMessageDeltaPayload: Decodable {
    let delta: DeltaContent
    let usage: Usage?

    struct DeltaContent: Decodable {
        let stop_reason: String?
    }
}

struct SSEErrorPayload: Decodable {
    let error: APIError
}
