import Foundation

/// Classifies profile/mention web links so they can open in-app instead of the
/// browser. Pure URL parsing — resolving a Mastodon URL to an account is the
/// feed service's job (`profile(forURL:)`).
public enum ProfileLink {
    /// The handle or DID from a Bluesky profile URL (`bsky.app/profile/<id>`), else nil.
    /// A post URL (`/profile/<id>/post/<rkey>`) is not a profile and returns nil.
    public static func blueskyID(from url: URL) -> String? {
        guard url.host == "bsky.app" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "profile" else { return nil }
        return parts[1]
    }

    /// Whether a URL is a Mastodon profile page (`https://instance/@user`).
    /// A status URL (`/@user/<id>`) or tag URL (`/tags/x`) is not a profile.
    public static func isMastodonProfileURL(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.count == 1 && parts[0].hasPrefix("@") && parts[0].count > 1
    }
}
