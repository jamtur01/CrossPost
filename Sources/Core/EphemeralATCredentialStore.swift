import ATProtoKit
import Foundation

/// Session storage for ATProtoKit that never touches the Keychain. ATProtoKit's
/// default writes the app password and refresh token to the login Keychain for every
/// session and never removes them, and CrossPost signs in often (each post, each
/// feed service), so copies piled up. CrossPost already keeps the app password in its
/// own Keychain item, so a session's copies only need to live as long as the session.
actor EphemeralATCredentialStore: ATCredentialStore {
    private var values: [String: Data] = [:]

    func loadValue(forKey key: String) -> Data? {
        values[key]
    }

    func saveValue(_ value: Data, forKey key: String) {
        values[key] = value
    }

    func deleteValue(forKey key: String) {
        values[key] = nil
    }
}
