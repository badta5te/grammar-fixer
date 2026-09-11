import Foundation

/// A failure that has something to say to a person. A silent failure costs
/// more here than elsewhere: somebody selected text, pressed the shortcut and
/// is waiting for it to be replaced. They cannot tell silence from work for
/// another minute.
public protocol UserFacingError: Error {
    var title: String { get }
    var message: String { get }
}

extension RoundTripError: UserFacingError {}

/// A message with no error type of its own: one-off cases such as "there is no
/// log yet". Declaring an enum for those would buy nothing.
public struct Notice: UserFacingError {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}
