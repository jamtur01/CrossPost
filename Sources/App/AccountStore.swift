import Foundation
import SwiftUI

/// Observable account configuration. Prefs in UserDefaults; secrets in Keychain.
@MainActor
final class AccountStore: ObservableObject {
    @AppStorage("mastodonInstanceURL") var mastodonInstanceURL: String = ""
    @AppStorage("mastodonMaxChars") var mastodonMaxChars: Int = TargetLimits.mastodonFallback
    @AppStorage("mastodonUsername") var mastodonUsername: String = ""   // your own acct, to avoid self-mentions
    @AppStorage("blueskyHandle") var blueskyHandle: String = ""

    private let credentials: CredentialStore

    init(credentials: CredentialStore = CredentialStore()) {
        self.credentials = credentials
    }

    var mastodonToken: String {
        get { (try? credentials.load(account: "mastodon-token")) ?? "" }
        set { try? persist(newValue, account: "mastodon-token") }
    }

    var blueskyAppPassword: String {
        get { (try? credentials.load(account: "bluesky-app-password")) ?? "" }
        set { try? persist(newValue, account: "bluesky-app-password") }
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
        guard let url = URL(string: text), url.host?.isEmpty == false else { return nil }
        return url
    }

    var limits: TargetLimits { TargetLimits(mastodonMax: mastodonMaxChars) }
}
