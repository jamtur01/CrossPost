import Foundation
import SwiftUI

/// Colours links, @mentions, and #hashtags in the platform accent so posts read
/// like a native client. Both Mastodon (tags stripped to plain text) and Bluesky
/// (plain text) arrive without styling, so we re-derive it here from the text.
enum RichText {
    private static let mentionPattern = try! NSRegularExpression(
        pattern: "(?<![\\w@])@[\\w.]+(@[\\w.]+)?")
    private static let hashtagPattern = try! NSRegularExpression(
        pattern: "(?<!\\w)#[\\p{L}0-9_]+")
    private static let linkDetector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func styled(_ text: String, accent: Color) -> AttributedString {
        var attributed = AttributedString(text)
        let full = NSRange(text.startIndex..<text.endIndex, in: text)

        linkDetector.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, let range = attributedRange(match.range, in: text, of: &attributed)
            else { return }
            attributed[range].foregroundColor = accent
            if let url = match.url { attributed[range].link = url }
        }
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
