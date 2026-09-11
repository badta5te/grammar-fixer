import Foundation
import Security

/// Where a key is kept. The protocol exists so that everything above it can be
/// tested without the Keychain, and so a person's key never has to be real for
/// a test to run.
public protocol SecretStore: Sendable {
    /// Nothing stored is `nil`, not a failure: an empty account is a first
    /// launch.
    func secret(for account: String) throws -> String?
    func store(_ secret: String, for account: String) throws
    func removeSecret(for account: String) throws
}

/// The system Keychain, one generic password per provider.
///
/// Per provider rather than one key for the app: trying DeepSeek for a week and
/// coming back to OpenAI must not cost the OpenAI key. A key is never written
/// to UserDefaults, so `defaults read` shows nothing worth stealing.
public struct Keychain: SecretStore {
    private let service: String

    public init(service: String = AppInfo.bundleIdentifier) {
        self.service = service
    }

    public func secret(for account: String) throws -> String? {
        var query = self.query(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError(status: status, account: account, action: .read)
        }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            // Something is stored under our name that we did not put there.
            // Reporting it beats returning nil, which would read as "no key"
            // and send the person to type a key they already typed.
            throw KeychainError(status: errSecDecode, account: account, action: .read)
        }
        return text
    }

    public func store(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)

        // Update first, add second. SecItemAdd on an account that already has
        // a key answers errSecDuplicateItem, and a key pasted over an old one
        // would silently never be saved.
        let update = SecItemUpdate(
            query(for: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw KeychainError(status: update, account: account, action: .write)
        }

        var item = query(for: account)
        item[kSecValueData as String] = data
        // So that the entry is recognisable in Keychain Access rather than
        // appearing as an anonymous generic password.
        item[kSecAttrLabel as String] = "\(AppInfo.name): \(account)"
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else {
            throw KeychainError(status: add, account: account, action: .write)
        }
    }

    public func removeSecret(for account: String) throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, account: account, action: .remove)
        }
    }

    /// `kSecUseDataProtectionKeychain` is stated rather than left to the
    /// default: the data protection keychain needs an entitlement this app does
    /// not have, and the file keychain is what an app signed with a local
    /// certificate can actually use.
    private func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: false,
        ]
    }
}

/// A Keychain refusal in words. A key that vanishes without a word is the worst
/// outcome here: the person retypes it, watches it disappear again and has
/// nothing to go on.
public struct KeychainError: UserFacingError, Equatable {
    public enum Action: Equatable, Sendable {
        case read, write, remove
    }

    public let status: OSStatus
    public let account: String
    public let action: Action

    public var title: String {
        switch action {
        case .read: "The key could not be read"
        case .write: "The key could not be saved"
        case .remove: "The key could not be removed"
        }
    }

    public var message: String {
        let reason = SecCopyErrorMessageString(status, nil) as String?
        return "The Keychain answered \(status)"
            + (reason.map { ": \($0)" } ?? "")
            + ".\n\nThe key for \(account) was left as it was."
    }
}
