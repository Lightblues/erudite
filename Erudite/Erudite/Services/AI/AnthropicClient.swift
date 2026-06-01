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
    /// Supports both official Anthropic API (x-api-key) and compatible proxies (Bearer token).
    /// The `requestId` from response headers is yielded as the first event via `.messageStart`.
    func stream(
        request: AnthropicRequest,
        apiKey: String,
        baseURL: String? = nil
    ) async throws -> (stream: AsyncThrowingStream<StreamEvent, Error>, requestId: String?) {
        let urlString = baseURL ?? "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: urlString) else {
            throw AIClientError.httpError(status: 0, message: "Invalid URL: \(urlString)")
        }

        let isOfficialAPI = urlString.contains("anthropic.com")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        // Auth: official API uses x-api-key, proxies typically use Bearer token
        if isOfficialAPI {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            // Enable prompt caching (official API only)
            urlRequest.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        } else {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.timeoutInterval = 120

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        // Capture request-id from response headers
        let requestId = httpResponse.value(forHTTPHeaderField: "x-request-id")
            ?? httpResponse.value(forHTTPHeaderField: "request-id")

        // Handle error status codes
        if httpResponse.statusCode != 200 {
            let errorBody = try await collectBytes(bytes)
            throw mapHTTPError(status: httpResponse.statusCode, body: errorBody)
        }

        // Return async stream that parses SSE events from the byte stream
        let eventStream: AsyncThrowingStream<StreamEvent, Error> = AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                // Buffer bytes and process at line boundaries.
                // We accumulate into a string buffer and flush after each newline.
                // This is much more efficient than byte-by-byte while still handling
                // partial chunks correctly (unlike bytes.lines which may skip empty lines).
                var buffer = ""
                var byteAccumulator = Data(capacity: 4096)

                do {
                    for try await byte in bytes {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        byteAccumulator.append(byte)

                        // Process on newline boundaries
                        if byte == UInt8(ascii: "\n") {
                            if let chunk = String(data: byteAccumulator, encoding: .utf8) {
                                byteAccumulator.removeAll(keepingCapacity: true)
                                let rawEvents = parser.feed(chunk)
                                for raw in rawEvents {
                                    if let event = SSEEventDecoder.decode(raw) {
                                        continuation.yield(event)
                                    }
                                }
                            }
                        }
                    }

                    // Flush remaining
                    if !byteAccumulator.isEmpty,
                       let chunk = String(data: byteAccumulator, encoding: .utf8) {
                        let rawEvents = parser.feed(chunk + "\n")
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

        return (stream: eventStream, requestId: requestId)
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
            return "Invalid API key. Open Settings (⌘,) to update your key."
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
