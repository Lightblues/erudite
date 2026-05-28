import Foundation

// MARK: - Anthropic HTTP Client

/// Low-level HTTP client for the Anthropic Messages API.
/// Handles streaming via URLSession.bytes and SSE parsing.
/// Does NOT handle tool loops — that's AgentRuntime's job.
final class AnthropicClient {

    private let session: URLSession
    private let apiVersion = "2023-06-01"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Streaming Request

    /// Send a streaming request to the Messages API.
    /// Returns an AsyncThrowingStream that yields parsed StreamEvents.
    func stream(
        request: AnthropicRequest,
        apiKey: String,
        baseURL: String? = nil
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let url = URL(string: baseURL ?? "https://api.anthropic.com/v1/messages")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        // Enable prompt caching
        urlRequest.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        urlRequest.timeoutInterval = 120

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        // Handle error status codes
        if httpResponse.statusCode != 200 {
            let errorBody = try await collectBytes(bytes)
            throw mapHTTPError(status: httpResponse.statusCode, body: errorBody)
        }

        // Return async stream that parses SSE events from the byte stream
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                var utf8Buffer = Data()

                do {
                    for try await byte in bytes {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        utf8Buffer.append(byte)

                        // Decode when we hit a newline (SSE events are line-delimited)
                        if byte == UInt8(ascii: "\n") {
                            if let chunk = String(data: utf8Buffer, encoding: .utf8) {
                                utf8Buffer.removeAll(keepingCapacity: true)
                                let rawEvents = parser.feed(chunk)
                                for raw in rawEvents {
                                    if let event = SSEEventDecoder.decode(raw) {
                                        continuation.yield(event)
                                    }
                                }
                            }
                        }

                        // Safety: flush buffer if it gets too large without newlines
                        if utf8Buffer.count > 65536 {
                            if let chunk = String(data: utf8Buffer, encoding: .utf8) {
                                utf8Buffer.removeAll(keepingCapacity: true)
                                let rawEvents = parser.feed(chunk)
                                for raw in rawEvents {
                                    if let event = SSEEventDecoder.decode(raw) {
                                        continuation.yield(event)
                                    }
                                }
                            }
                        }
                    }

                    // Stream ended — flush any remaining data
                    if !utf8Buffer.isEmpty, let chunk = String(data: utf8Buffer, encoding: .utf8) {
                        let rawEvents = parser.feed(chunk)
                        for raw in rawEvents {
                            if let event = SSEEventDecoder.decode(raw) {
                                continuation.yield(event)
                            }
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Helpers

    private func collectBytes(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 10_000 { break } // Don't read forever on error
        }
        return data
    }

    private func mapHTTPError(status: Int, body: Data) -> AIClientError {
        let message: String
        if let errorResponse = try? JSONDecoder().decode(APIErrorWrapper.self, from: body) {
            message = errorResponse.error.message
        } else {
            message = String(data: body, encoding: .utf8) ?? "Unknown error"
        }

        switch status {
        case 401:
            return .invalidAPIKey
        case 429:
            return .rateLimited(message: message)
        case 529:
            return .overloaded
        default:
            return .httpError(status: status, message: message)
        }
    }
}

// MARK: - Error Types

enum AIClientError: LocalizedError {
    case invalidResponse
    case invalidAPIKey
    case httpError(status: Int, message: String)
    case rateLimited(message: String)
    case overloaded

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from API"
        case .invalidAPIKey:
            return "Invalid API key. Please check your key in Config.json."
        case .httpError(let status, let message):
            return "HTTP \(status): \(message)"
        case .rateLimited(let message):
            return "Rate limited: \(message)"
        case .overloaded:
            return "API is overloaded. Please try again in a moment."
        }
    }
}

// MARK: - Internal Decode Helpers

private struct APIErrorWrapper: Decodable {
    let error: APIError
}
