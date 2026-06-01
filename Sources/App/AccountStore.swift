import Foundation
import SwiftUI

/// Observable account configuration. Prefs in UserDefaults; secrets in Keychain.
@MainActor
final class AccountStore: ObservableObject {
    @AppStorage("mastodonInstanceURL") var mastodonInstanceURL: String = ""
    @AppStorage("mastodonMaxChars") var mastodonMaxChars: Int = TargetLimits.mastodonFallback
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

    var hasMastodon: Bool { !mastodonInstanceURL.isEmpty && !mastodonToken.isEmpty }
    var hasBluesky: Bool { !blueskyHandle.isEmpty && !blueskyAppPassword.isEmpty }

    var limits: TargetLimits { TargetLimits(mastodonMax: mastodonMaxChars) }
}
