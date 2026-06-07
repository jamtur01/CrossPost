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

    static func styled(_ input: AttributedString, accent: Color) -> AttributedString {
        var attributed = input
        let text = String(attributed.characters)
        let full = NSRange(text.startIndex..<text.endIndex, in: text)

        // Colour links that arrived pre-attributed (Mastodon anchors, Bluesky facets).
        for range in attributed.runs.compactMap({ $0.link == nil ? nil : $0.range }) {
            attributed[range].foregroundColor = accent
        }
        // Detect bare URLs in plain text and turn them into coloured links.
        linkDetector.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, let url = match.url,
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
