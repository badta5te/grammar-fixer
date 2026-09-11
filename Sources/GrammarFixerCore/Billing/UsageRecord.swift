import Foundation

/// One round, as far as money is concerned.
///
/// Tokens are stored and dollars are not. The price table is editable, so a
/// model that had no price when the round happened gets one the moment
/// somebody types it in, and the month it belongs to fills itself in
/// retroactively. Storing the amount instead would leave those rounds worth
/// nothing for ever.
public struct UsageRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    /// Which provider was paid. The same model name is sold by more than one
    /// of them at more than one price.
    public var provider: String
    public var model: String
    public var promptTokens: Int
    public var completionTokens: Int

    /// The provider reported no usage and these numbers were guessed from the
    /// text. Kept on the record rather than worked out later, because it is a
    /// fact about the round that nothing afterwards can recover.
    public var isEstimated: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        provider: String,
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        isEstimated: Bool = false
    ) {
        self.id = id
        self.date = date
        self.provider = provider
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.isEstimated = isEstimated
    }
}
