import Foundation

/// Ответ провайдера как поток строк. Код ответа отделён от тела намеренно:
/// решение о повторе и о переводе отказа в человеческий текст принимается по
/// голове ответа, до того как наружу уйдёт хоть один кусок текста.
public struct HTTPStream: Sendable {
    public let status: Int
    public let lines: AsyncThrowingStream<String, any Error>

    public init(status: Int, lines: AsyncThrowingStream<String, any Error>) {
        self.status = status
        self.lines = lines
    }
}

/// Шов над сетью. Подменяется в тестах целиком, поэтому ни повтор запроса, ни
/// перевод кодов ответа не требуют живого провайдера.
public protocol HTTPLineStreaming: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPStream
}

/// Единственная часть слоя модели, которая говорит с сетью, и единственная
/// непокрытая тестами: всё решающее живёт выше этого шва.
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
