import Foundation

/// Builds bsky.app web URLs — the one place the `https://bsky.app/...` shapes and
/// the at:// record-key extraction live, shared by the poster and feed service.
enum BlueskyURL {
    private static let base = "https://bsky.app"

    /// The record key (last path component) of an at:// URI, or nil when absent.
    /// Requires the full `at://authority/collection/rkey` shape: a rootless URI
    /// (`at://did:plc:x`) has no record key, and returning its authority would
    /// produce a bogus post URL.
    static func rkey(from atURI: String) -> String? {
        guard atURI.hasPrefix("at://") else { return nil }
        let segments = atURI.dropFirst("at://".count).split(separator: "/")
        guard segments.count >= 3, let last = segments.last else { return nil }
        return String(last)
    }

    /// A profile page URL string for a handle or DID.
    static func profile(_ handleOrID: String) -> String { "\(base)/profile/\(handleOrID)" }

    /// A hashtag page URL string.
    static func hashtag(_ tag: String) -> String { "\(base)/hashtag/\(tag)" }

    /// A post's web URL from its at:// record URI and the author's handle, or nil
    /// when the URI carries no record key (so an unlinkable post stays nil).
    static func post(recordURI: String, handle: String) -> String? {
        guard let rkey = rkey(from: recordURI) else { return nil }
        return "\(profile(handle))/post/\(rkey)"
    }
}
