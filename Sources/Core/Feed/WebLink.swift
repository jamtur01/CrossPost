import Foundation

/// Guards links derived from untrusted remote content (post HTML, richtext
/// facets, detected bare URLs). Only `http`/`https` URLs are safe to turn into a
/// tappable link or hand to the system to open — this blocks `file://`, custom
/// app schemes, and the like that a malicious post could otherwise smuggle in.
enum WebLink {
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
