import Foundation

/// Asking a provider which models it has.
///
/// The app deliberately knows no model names of its own. Any list written into
/// it would be stale the next time a provider renames something, and they do
/// that far more often than this app is released — which is the whole reason
/// the field beside this list stays free to type in.
public protocol ModelListing: Sendable {
    func models() async throws -> [String]
}

/// The parts of that answer both adapters share.
enum ModelCatalog {
    /// OpenRouter answers with several hundred entries. A menu of several
    /// hundred is not a menu, and the newest are what somebody opening this
    /// list came for.
    static let limit = 50

    /// Words that never belong to a model that can rewrite a sentence. A
    /// provider's list is everything it sells: transcription, speech, images,
    /// embeddings. Left in, they bury the handful of models that can do the
    /// job.
    ///
    /// Hiding one by mistake costs nothing that cannot be undone: the name can
    /// still be typed into the field by hand.
    private static let notForText = [
        "whisper", "tts", "dall-e", "embed", "moderation", "rerank",
        "audio", "image", "video", "sora", "transcribe", "realtime",
    ]

    /// Newest first when the provider dates its models, alphabetical when it
    /// does not: either way the order has to be one somebody can look a name up
    /// in.
    static func arrange(_ models: [(id: String, date: String?)]) -> [String] {
        let kept = models.filter { model in
            let name = model.id.lowercased()
            return !name.isEmpty && !notForText.contains { name.contains($0) }
        }
        let dated = kept.filter { $0.date != nil }
        let ordered = dated.count == kept.count
            ? kept.sorted { ($0.date ?? "") > ($1.date ?? "") }
            : kept.sorted { $0.id < $1.id }
        return Array(ordered.map(\.id).prefix(limit))
    }

    /// Every provider answers this question with `{"data": [...]}`; what sits
    /// inside the entries is what differs.
    struct Answer: Decodable {
        let data: [Entry]?

        struct Entry: Decodable {
            let id: String?
            /// OpenAI-compatible servers date a model with a Unix timestamp,
            /// Anthropic with an ISO-8601 string. Both sort correctly as text
            /// once the number is padded.
            let created: Int?
            let createdAt: String?

            var date: String? {
                if let createdAt { return createdAt }
                if let created { return String(format: "%012d", created) }
                return nil
            }

            enum CodingKeys: String, CodingKey {
                case id
                case created
                case createdAt = "created_at"
            }
        }
    }

    static func parse(_ body: String) throws -> [String] {
        guard let data = body.data(using: .utf8),
              let answer = try? JSONDecoder().decode(Answer.self, from: data),
              let entries = answer.data
        else {
            // An answer nobody can read is not an empty list. Showing it as one
            // would say "this provider has no models", which is never true.
            throw LLMError.modelsUnreadable
        }
        return arrange(entries.compactMap { entry in
            guard let id = entry.id?.trimmed, !id.isEmpty else { return nil }
            return (id: id, date: entry.date)
        })
    }

    /// The whole body rather than the first few lines an error needs. Capped
    /// all the same: this is somebody else's server deciding how much to send.
    static func body(of response: HTTPStream, limit: Int = 2_000_000) async -> String {
        var collected: [String] = []
        var length = 0
        do {
            for try await line in response.lines {
                collected.append(line)
                length += line.count
                if length >= limit { break }
            }
        } catch {
            // A body that breaks off part way is handled by the parser, which
            // will not read it and will say so.
        }
        return collected.joined(separator: "\n")
    }
}
