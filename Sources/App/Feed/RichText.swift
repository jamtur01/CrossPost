import Foundation
import SwiftUI

/// Colours links, @mentions, and #hashtags in the platform accent so posts read
/// like a native client. Mastodon arrives with real anchor links already attached
/// (see `HTMLRenderer`); Bluesky arrives as plain text, so we detect bare URLs,
/// @mentions, and #hashtags here. Existing links are preserved, never rewritten.
enum RichText {
    private static let mentionPattern = try! NSRegularExpression(
        pattern: "(?<![\\w@])@[\\w.]+(@[\\w.]+)?")
    private static let hashtagPattern = try! NSRegularExpression(
        pattern: "(?<!\\w)#[\\p{L}0-9_]+")
    private static let linkDetector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func styled(_ input: AttributedString, accent: Color) -> AttributedString {
        var attributed = input
        let text = String(attributed.characters)
        let full = NSRange(text.startIndex..<text.endIndex, in: text)

        // Colour links that arrived pre-attributed (e.g. Mastodon mentions/links).
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
        // Colour @mentions and #hashtags (Bluesky plain text; harmless if linked).
        for pattern in [mentionPattern, hashtagPattern] {
            pattern.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match, let range = attributedRange(match.range, in: text, of: &attributed)
                else { return }
                attributed[range].foregroundColor = accent
            }
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
