import Foundation

/// Отказы на пути к модели. Текст английский, как и весь интерфейс.
///
/// Ключ в сообщения не попадает никогда, в том числе из тела ответа провайдера:
/// провайдеры иногда отражают присланный ключ в описании ошибки, а сообщение
/// видно на экране через плечо.
public enum LLMError: UserFacingError, Equatable {
    case noConfiguration(path: String)
    case brokenConfiguration(path: String, reason: String)
    case noKey(path: String)
    case noConnection
    case timedOut
    case unauthorized(String?)
    case rateLimited(String?)
    case providerRejected(String?)
    case providerUnavailable(status: Int, detail: String?)
    case emptyAnswer

    public var title: String {
        switch self {
        case .noConfiguration: "No provider configured"
        case .brokenConfiguration: "The provider file cannot be read"
        case .noKey: "No API key"
        case .noConnection: "No connection"
        case .timedOut: "The model took too long"
        case .unauthorized: "The API key was refused"
        case .rateLimited: "Rate limit reached"
        case .providerRejected: "The provider refused the request"
        case .providerUnavailable: "The provider is unavailable"
        case .emptyAnswer: "The model returned nothing"
        }
    }

    public var message: String {
        switch self {
        case .noConfiguration(let path):
            "Create \(path) with your provider, model and API key. See the README for the shape."
        case .brokenConfiguration(let path, let reason):
            "\(path) is not valid JSON: \(reason)"
        case .noKey(let path):
            "Add an apiKey to \(path), or set GRAMMARFIXER_API_KEY before launching."
        case .noConnection:
            "GrammarFixer could not reach the provider. Your text was left untouched."
        case .timedOut:
            "The request was given up on. Your text was left untouched, so you can try again."
        case .unauthorized(let detail):
            "The provider rejected the key. Check that it is current and has access to the model."
                + Self.suffix(detail)
        case .rateLimited(let detail):
            "The provider is throttling requests. Wait a moment and try again." + Self.suffix(detail)
        case .providerRejected(let detail):
            "The request was refused, most often because the model name is wrong." + Self.suffix(detail)
        case .providerUnavailable(let status, let detail):
            "The provider answered with HTTP \(status). This is on their side, so try again shortly."
                + Self.suffix(detail)
        case .emptyAnswer:
            "The model answered with no text at all. Your text was left untouched."
        }
    }

    private static func suffix(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "" }
        return "\n\n" + Redaction.withoutKeys(detail)
    }

    /// Ошибки сети приходят из URLSession и переводятся здесь, чтобы человек
    /// видел причину, а не номер.
    static func from(_ error: any Error) -> LLMError {
        if let error = error as? LLMError { return error }
        guard let error = error as? URLError else { return .noConnection }
        switch error.code {
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed:
            return .noConnection
        default: return .noConnection
        }
    }

    /// Перевод кода ответа в отказ. Без тела ответа остаётся один номер, по
    /// которому человек ничего сделать не может.
    static func from(status: Int, body: String) -> LLMError {
        let detail = ProviderErrorBody.message(fromBody: body)
        switch status {
        case 401, 403: return .unauthorized(detail)
        case 429: return .rateLimited(detail)
        case 400..<500: return .providerRejected(detail)
        default: return .providerUnavailable(status: status, detail: detail)
        }
    }
}
