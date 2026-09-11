import Foundation

/// The provider's answer as a stream of lines. The status is deliberately kept
/// apart from the body: whether to retry, and how to turn a refusal into words
/// a person can act on, is decided from the head of the response, before a
/// single piece of text has left this layer.
public struct HTTPStream: Sendable {
    public let status: Int
    public let lines: AsyncThrowingStream<String, any Error>

    public init(status: Int, lines: AsyncThrowingStream<String, any Error>) {
        self.status = status
        self.lines = lines
    }
}

/// The seam over the network. Tests replace it whole, so neither the retry nor
/// the translation of status codes needs a live provider.
public protocol HTTPLineStreaming: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPStream
}

/// The only part of the model layer that talks to the network, and the only
/// part no test covers: everything that decides anything lives above the seam.
public struct URLSessionLineStream: HTTPLineStreaming {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPStream {
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPStream(status: status, lines: AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        })
    }
}
