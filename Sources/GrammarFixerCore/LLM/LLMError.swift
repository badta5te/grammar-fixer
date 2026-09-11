import Foundation

/// Refusals on the way to the model.
///
/// The key never reaches a message, not even by way of the provider's own
/// response body: providers sometimes echo the key they were sent back in the
/// error description, and a message on screen is readable over a shoulder.
public enum LLMError: UserFacingError, Equatable {
    case notConfigured
    case noKey
    case noModel
    case badAddress(String)
    case unknownProvider(String)
    case noConnection
    case timedOut
    case unauthorized(String?)
    case rateLimited(String?)
    case providerRejected(String?)
    case providerUnavailable(status: Int, detail: String?)
    case emptyAnswer
    case answerTruncated
    case modelsUnreadable
    case unexpected(String)

    public var title: String {
        switch self {
        case .notConfigured: "No provider configured"
        case .noKey: "No API key"
        case .noModel: "No model chosen"
        case .badAddress: "The address cannot be used"
        case .unknownProvider: "Unknown provider"
        case .noConnection: "No connection"
        case .timedOut: "The model took too long"
        case .unauthorized: "The API key was refused"
        case .rateLimited: "Rate limit reached"
        case .providerRejected: "The provider refused the request"
        case .providerUnavailable: "The provider is unavailable"
        case .emptyAnswer: "The model returned nothing"
        case .answerTruncated: "The answer was cut off"
        case .answerTruncated:
            "The model stopped before it finished, which happens with a very long selection. "
                + "Your text was left untouched rather than replaced with half a correction."
        case .modelsUnreadable: "The list of models could not be read"
        case .unexpected: "Something went wrong"
        }
    }

    public var message: String {
        switch self {
        case .notConfigured:
            "Open Settings from the menu bar and choose a provider, a model and a key."
        case .noKey:
            "Open Settings and paste your API key for the chosen provider. "
                + "The key is kept in the Keychain, never in a file."
        case .noModel:
            "Open Settings and type the name of the model to use. "
                + "Take the name from your provider's own documentation: they rename models often."
        case .badAddress(let address):
            "\(address) is not an address GrammarFixer can send a request to. "
                + "It needs to look like https://example.com/v1."
        case .unknownProvider(let name):
            "\(name) is not one of \(ProviderPreset.namesForMessage). "
                + "Choose one in Settings, or pick your own address and type it in."
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
        case .answerTruncated:
            "The model stopped before it finished, which happens with a very long selection. "
                + "Your text was left untouched rather than replaced with half a correction."
        case .modelsUnreadable:
            "The provider answered with something other than a list of models. "
                + "Type the model name in by hand instead."
        case .unexpected(let detail):
            "GrammarFixer could not finish the request, and your text was left untouched."
                + Self.suffix(detail)
        }
    }

    private static func suffix(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "" }
        return "\n\n" + Redaction.withoutKeys(detail)
    }

    /// Network failures arrive from URLSession and are translated here, so the
    /// person sees a cause rather than a number.
    static func from(_ error: any Error) -> LLMError {
        if let error = error as? LLMError { return error }
        // Not every failure is the network. Calling an unrelated error a
        // network problem sends the person to fix their connection instead of
        // their configuration.
        guard let error = error as? URLError else {
            return .unexpected(String(describing: error))
        }
        switch error.code {
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed:
            return .noConnection
        default:
            // A blocked plain-HTTP address, a TLS failure, a cancelled request:
            // none of these are the connection, and calling them that sends the
            // person to their Wi-Fi instead of their configuration file.
            return .unexpected(error.localizedDescription)
        }
    }

    /// Turns a status code into a refusal. Without the response body only a
    /// number is left, and a number is nothing a person can act on.
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
