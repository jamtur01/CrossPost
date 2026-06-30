import Foundation
import SwiftUI

/// Colours the *interactive* parts of post/bio text in the platform accent so they
/// read like a native client. Links that arrived pre-attributed (Mastodon anchors,
/// Bluesky facets) are coloured, and bare URLs in plain text are detected and linked.
/// Plain "@…"/"#…" text that isn't a real, resolvable link is left untouched — so
/// anything coloured is genuinely tappable (e.g. "@cat" in a bio stays plain text).
enum RichText {
    private static let linkDetector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

    private final class Box { let value: AttributedString; init(_ value: AttributedString) { self.value = value } }
    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 500
        return cache
    }()

    /// `cacheKey` (e.g. the post id, which is platform-prefixed so it captures the
    /// accent too) memoises the result so the NSDataDetector pass doesn't re-run on
    /// every `body` evaluation while scrolling. The post's text is folded into the
    /// key so an edit (same id, new body) recomputes instead of serving stale text.
    static func styled(_ input: AttributedString, accent: Color, cacheKey: String? = nil) -> AttributedString {
        let key = cacheKey.map { "\($0)#\(fingerprint(input))" as NSString }
        if let key, let hit = cache.object(forKey: key) { return hit.value }
        let result = compute(input, accent: accent)
        if let key { cache.setObject(Box(result), forKey: key) }
        return result
    }

    /// Identity of the rendered input: its text plus every link run's href, so an
    /// edit that changes the body — or a facet whose URL changed under the same
    /// visible label — misses the cache instead of serving a stale render.
    private static func fingerprint(_ input: AttributedString) -> Int {
        var hasher = Hasher()
        hasher.combine(String(input.characters))
        for run in input.runs where run.link != nil {
            hasher.combine(run.link?.absoluteString)
        }
        return hasher.finalize()
    }

    private static func compute(_ input: AttributedString, accent: Color) -> AttributedString {
        var attributed = input
        let text = String(attributed.characters)
        let full = NSRange(text.startIndex..<text.endIndex, in: text)

        // Colour links that arrived pre-attributed (Mastodon anchors, Bluesky facets).
        for range in attributed.runs.compactMap({ $0.link == nil ? nil : $0.range }) {
            attributed[range].foregroundColor = accent
        }
        // Detect bare URLs in plain text and turn them into coloured links.
        linkDetector.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, let url = match.url, WebLink.isOpenable(url),
                  let range = attributedRange(match.range, in: text, of: &attributed),
                  attributed[range].link == nil
            else { return }
            attributed[range].link = url
            attributed[range].foregroundColor = accent
        }
        return attributed
    }

    private static func attributedRange(
        _ nsRange: NSRange, in text: String, of attributed: inout AttributedString
    ) -> Range<AttributedString.Index>? {
        guard let stringRange = Range(nsRange, in: text),
              let low = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let high = AttributedString.Index(stringRange.upperBound, within: attributed)
        else { return nil }
        return low..<high
    }
}
