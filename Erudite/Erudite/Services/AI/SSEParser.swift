import Foundation

// MARK: - SSE Parser

/// Parses raw Server-Sent Events text into structured events.
/// Stateful: buffers partial lines across chunk boundaries.
///
/// SSE spec: https://html.spec.whatwg.org/multipage/server-sent-events.html
struct SSEParser {
    private var lineBuffer: String = ""
    private var currentEvent: String?
    private var currentData: [String] = []

    /// Feed a chunk of text (from URLSession bytes). Returns zero or more parsed raw events.
    mutating func feed(_ chunk: String) -> [SSERawEvent] {
        var events: [SSERawEvent] = []
        lineBuffer += chunk

        while true {
            // Find next line ending (\n, \r\n, or \r)
            guard let newlineRange = lineBuffer.rangeOfCharacter(from: .newlines) else {
                break // No complete line yet — wait for more data
            }

            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])

            // Advance past the newline character(s)
            var endIndex = newlineRange.upperBound
            if lineBuffer[newlineRange.lowerBound] == "\r",
               endIndex < lineBuffer.endIndex,
               lineBuffer[endIndex] == "\n" {
                // Handle \r\n as single newline
                endIndex = lineBuffer.index(after: endIndex)
            }
            lineBuffer = String(lineBuffer[endIndex...])

            if line.isEmpty {
                // Empty line = dispatch current event
                if !currentData.isEmpty {
                    events.append(SSERawEvent(
                        event: currentEvent,
                        data: currentData.joined(separator: "\n")
                    ))
                }
                currentEvent = nil
                currentData = []
            } else if line.hasPrefix(":") {
                // Comment line (used as keep-alive ping) — ignore
                continue
            } else if line.hasPrefix("event:") {
                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let value = String(line.dropFirst(5))
                // Trim only leading space (SSE spec: one optional space after colon)
                let trimmed = value.hasPrefix(" ") ? String(value.dropFirst()) : value
                currentData.append(trimmed)
            } else if line.hasPrefix("id:") {
                // We don't use event IDs — skip
                continue
            } else if line.hasPrefix("retry:") {
                // We don't use retry — skip
                continue
            }
            // Lines without a colon that aren't empty are treated as field name with empty value
            // (per spec), but Anthropic doesn't send these — safe to ignore
        }

        return events
    }

    /// Reset parser state (e.g., on reconnection)
    mutating func reset() {
        lineBuffer = ""
        currentEvent = nil
        currentData = []
    }
}

// MARK: - SSE Raw Event

struct SSERawEvent {
    let event: String?   // e.g. "message_start", "content_block_delta"
    let data: String     // JSON payload string
}

// MARK: - SSE Event Decoder

/// Decodes SSERawEvent (event name + JSON data) into typed StreamEvent
enum SSEEventDecoder {
    private static let decoder = JSONDecoder()

    static func decode(_ raw: SSERawEvent) -> StreamEvent? {
        guard let data = raw.data.data(using: .utf8) else { return nil }

        switch raw.event {
        case "message_start":
            guard let payload = try? decoder.decode(MessageStartPayload.self, from: data) else {
                return nil
            }
            return .messageStart(payload)

        case "content_block_start":
            guard let payload = try? decoder.decode(SSEContentBlockStartPayload.self, from: data) else {
                return nil
            }
            return .contentBlockStart(index: payload.index, contentBlock: payload.content_block)

        case "content_block_delta":
            guard let payload = try? decoder.decode(SSEContentBlockDeltaPayload.self, from: data) else {
                return nil
            }
            let delta: ContentDelta
            switch payload.delta.type {
            case "text_delta":
                delta = .textDelta(payload.delta.text ?? "")
            case "input_json_delta":
                delta = .inputJSONDelta(payload.delta.partial_json ?? "")
            default:
                return nil
            }
            return .contentBlockDelta(index: payload.index, delta: delta)

        case "content_block_stop":
            guard let payload = try? decoder.decode(SSEContentBlockStopPayload.self, from: data) else {
                return nil
            }
            return .contentBlockStop(index: payload.index)

        case "message_delta":
            guard let payload = try? decoder.decode(SSEMessageDeltaPayload.self, from: data) else {
                return nil
            }
            return .messageDelta(stopReason: payload.delta.stop_reason, usage: payload.usage)

        case "message_stop":
            return .messageStop

        case "ping":
            return .ping

        case "error":
            guard let payload = try? decoder.decode(SSEErrorPayload.self, from: data) else {
                return nil
            }
            return .error(payload.error)

        default:
            // Unknown event type — skip gracefully
            return nil
        }
    }
}
