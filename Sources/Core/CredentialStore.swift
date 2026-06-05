import Foundation
import Security

/// Reads and writes named secrets. Lets callers (and tests) substitute storage
/// for the real Keychain, which is an external boundary we don't exercise in unit tests.
public protocol SecretStoring: Sendable {
    func save(_ value: String, account: String) throws
    func load(account: String) throws -> String?
    func delete(account: String) throws
}

/// Non-persistent secret storage. Used when the app runs as a unit-test host, where
/// touching the real Keychain triggers a SecurityAgent password prompt on every
/// rebuild (the re-signed binary is no longer in the item's ACL).
public final class EphemeralSecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    public init() {}

    public func save(_ value: String, account: String) throws {
        lock.withLock { items[account] = value }
    }

    public func load(account: String) throws -> String? {
        lock.withLock { items[account] }
    }

    public func delete(account: String) throws {
        lock.withLock { items[account] = nil }
    }
}

/// Stores secrets as generic-password items in the login Keychain, keyed by (service, account).
public struct CredentialStore: SecretStoring, Sendable {
    public enum KeychainError: Error, CustomStringConvertible, LocalizedError {
        case unexpectedStatus(OSStatus)
        case dataEncoding
        public var description: String {
            switch self {
            case .unexpectedStatus(let s): return "Keychain error (OSStatus \(s))"
            case .dataEncoding: return "Could not encode/decode Keychain value"
            }
        }
        public var errorDescription: String? { description }
    }

    private let service: String

    public init(service: String = "net.kartar.crosspost") {
        self.service = service
    }

    public func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataEncoding }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary) // ignore result; ensures overwrite
        var add = base
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func load(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataEncoding
        }
        return value
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
