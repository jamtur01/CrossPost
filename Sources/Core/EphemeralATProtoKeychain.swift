import ATProtoKit
import Foundation

/// Session storage for ATProtoKit that never touches the Keychain. ATProtoKit's
/// default writes the app password and refresh token to the login Keychain under
/// a fresh UUID for every session and never removes them, and CrossPost signs in
/// often (each post, each feed service), so copies piled up. CrossPost already
/// keeps the app password in its own Keychain item, so a session's copies only
/// need to live as long as the session.
actor EphemeralATProtoKeychain: SecureKeychainProtocol {
    nonisolated let identifier = UUID()
    private var accessToken: String?
    private var refreshToken: String?
    private var password: String?

    struct MissingValue: Error {}

    private func required(_ value: String?) throws -> String {
        guard let value else { throw MissingValue() }
        return value
    }

    func retrieveAccessToken() throws -> String {
        try required(accessToken)
    }

    func saveAccessToken(_ accessToken: String) {
        self.accessToken = accessToken
    }

    func deleteAccessToken() {
        accessToken = nil
    }

    func savePassword(_ password: String) {
        self.password = password
    }

    func retrievePassword() throws -> String {
        try required(password)
    }

    func updatePassword(_ newPassword: String) {
        password = newPassword
    }

    func deletePassword() {
        password = nil
    }

    func saveRefreshToken(_ refreshToken: String) {
        self.refreshToken = refreshToken
    }

    func retrieveRefreshToken() throws -> String {
        try required(refreshToken)
    }

    func updateRefreshToken(_ newRefreshToken: String) {
        refreshToken = newRefreshToken
    }

    func deleteRefreshToken() {
        refreshToken = nil
    }
}
