import Foundation
import SwiftUI

/// Observable account configuration. Prefs in UserDefaults; secrets in Keychain.
@MainActor
final class AccountStore: ObservableObject {
    @AppStorage("mastodonInstanceURL", store: AccountStore.defaults) var mastodonInstanceURL: String = ""
    @AppStorage("mastodonMaxChars", store: AccountStore.defaults) var mastodonMaxChars: Int = TargetLimits.mastodonFallback
    @AppStorage("mastodonUsername", store: AccountStore.defaults) var mastodonUsername: String = ""   // your own acct, to avoid self-mentions
    @AppStorage("blueskyHandle", store: AccountStore.defaults) var blueskyHandle: String = ""

    private let credentials: SecretStoring

    init(credentials: SecretStoring? = nil) {
        self.credentials = credentials ?? Self.defaultCredentialStore()
    }

    /// Real Keychain in normal runs; ephemeral storage when hosted by the unit-test
    /// runner, so launching the test host doesn't trigger a Keychain password prompt.
    private static func defaultCredentialStore() -> SecretStoring {
        return isUnderTests ? EphemeralSecretStore() : CredentialStore()
    }

    /// UserDefaults for stored prefs. The standard suite in normal runs, but a
    /// throwaway suite under the unit-test host: tests share the app's bundle id and
    /// would otherwise overwrite the real app's instance URL and handle in `.standard`.
    static let defaults: UserDefaults = {
        guard isUnderTests, let suite = UserDefaults(suiteName: "net.kartar.crosspost.tests") else {
            return .standard
        }
        return suite
    }()

    nonisolated private static var isUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The most recent Keychain write failure, for Settings to surface; cleared by
    /// the next successful write. Secret writes must not fail silently — a token
    /// that never landed in the Keychain would otherwise just "sign out" the user
    /// at some later launch with no explanation.
    @Published var keychainError: String?

    var mastodonToken: String {
        get { (try? credentials.load(account: "mastodon-token")) ?? "" }
        set { persistReportingFailure(newValue, account: "mastodon-token") }
    }

    var blueskyAppPassword: String {
        get { (try? credentials.load(account: "bluesky-app-password")) ?? "" }
        set { persistReportingFailure(newValue, account: "bluesky-app-password") }
    }

    private func persistReportingFailure(_ value: String, account: String) {
        do {
            try persist(value, account: account)
            keychainError = nil
        } catch {
            keychainError = error.userMessage
            Log.auth.error("keychain write for \(account, privacy: .public) failed: \(error)")
        }
    }

    private func persist(_ value: String, account: String) throws {
        if value.isEmpty {
            try credentials.delete(account: account)
        } else {
            try credentials.save(value, account: account)
        }
    }

    func saveMastodon(instanceURL: String, token: String, maxChars: Int, username: String?) throws {
        try persist(token, account: "mastodon-token")
        mastodonInstanceURL = instanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        mastodonMaxChars = maxChars
        if let username { mastodonUsername = username }
    }

    func saveBluesky(handle: String, appPassword: String) throws {
        try persist(appPassword, account: "bluesky-app-password")
        blueskyHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasMastodon: Bool { !mastodonInstanceURL.isEmpty && !mastodonToken.isEmpty }
    var hasBluesky: Bool { !blueskyHandle.isEmpty && !blueskyAppPassword.isEmpty }

    /// The instance URL normalized for networking: a bare host like `hachyderm.io`
    /// gets an `https://` scheme, surrounding whitespace and trailing slashes are dropped.
    var mastodonBaseURL: URL? {
        Self.normalizedMastodonBaseURL(from: mastodonInstanceURL)
    }

    nonisolated static func normalizedMastodonBaseURL(from rawValue: String) -> URL? {
        var text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        // The bearer token rides every request; only loopback may skip TLS
        // (self-hosted dev instances), anything remote must be https.
        switch url.scheme?.lowercased() {
        case "https": return url
        case "http" where ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()): return url
        default: return nil
        }
    }

    var limits: TargetLimits { TargetLimits(mastodonMax: mastodonMaxChars) }
}
