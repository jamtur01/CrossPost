import Foundation

/// Classifies profile/mention web links so they can open in-app instead of the
/// browser. Pure URL parsing — resolving a Mastodon URL to an account is the
/// feed service's job (`profile(forURL:)`).
enum ProfileLink {
    /// The handle or DID from a Bluesky profile URL (`bsky.app/profile/<id>`), else nil.
    /// A post URL (`/profile/<id>/post/<rkey>`) is not a profile and returns nil.
    static func blueskyID(from url: URL) -> String? {
        guard url.host == "bsky.app" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "profile" else { return nil }
        return parts[1]
    }

    /// Whether a URL is a Mastodon profile page (`https://instance/@user` or the
    /// remote `https://instance/@user@host` form). A status URL (`/@user/<id>`) or
    /// tag URL (`/tags/x`) is not a profile. The username must use Mastodon's
    /// charset ([A-Za-z0-9_]), which rejects look-alikes like `medium.com/@a.b`.
    /// A bare `/@name` on a non-Mastodon host can't be ruled out by URL alone; it
    /// falls through to a WebFinger lookup that fails into the browser.
    static func isMastodonProfileURL(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, parts[0].hasPrefix("@") else { return false }
        let username = parts[0].dropFirst().split(separator: "@", maxSplits: 1).first ?? ""
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return !username.isEmpty && username.allSatisfy { allowed.contains($0) }
    }
}
