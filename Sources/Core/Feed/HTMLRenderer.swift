import Foundation

public enum HTMLRenderer {
    /// Convert Mastodon's limited HTML into an AttributedString: `</p>` → blank
    /// line, `<br>` → newline, `<a href>` → a link run (visible label as text,
    /// href as `.link`), other tags stripped, entities decoded.
    public static func renderAttributed(_ html: String) -> AttributedString {
        var s = html
        s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)

        var result = AttributedString()
        let nsInput = s as NSString
        var cursor = 0
        for match in anchorMatches(in: s) {
            if match.range.location > cursor {
                let preLength = match.range.location - cursor
                let pre = nsInput.substring(with: NSRange(location: cursor, length: preLength))
                result.append(AttributedString(plainText(pre)))
            }
            result.append(anchorPiece(match, in: s))
            cursor = match.range.location + match.range.length
        }
        if cursor < nsInput.length {
            result.append(AttributedString(plainText(nsInput.substring(from: cursor))))
        }
        return trimmed(result)
    }

    private static func anchorMatches(in input: String) -> [NSTextCheckingResult] {
        let pattern = #"<a\b[^>]*\bhref\s*=\s*(['"])(.*?)\1[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let nsInput = input as NSString
        return regex.matches(in: input, range: NSRange(location: 0, length: nsInput.length))
    }

    private static func anchorPiece(_ match: NSTextCheckingResult, in input: String) -> AttributedString {
        guard match.numberOfRanges == 4,
              let hrefRange = Range(match.range(at: 2), in: input),
              let labelRange = Range(match.range(at: 3), in: input)
        else { return AttributedString() }

        let href = decodeEntities(String(input[hrefRange]))
        let label = plainText(String(input[labelRange]))
        var piece = AttributedString(label.isEmpty ? href : label)
        if let url = URL(string: href), WebLink.isOpenable(url) { piece.link = url }
        return piece
    }

    /// Strip remaining tags and decode entities; used for non-anchor spans and anchor labels.
    private static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(stripped)
    }

    private static func trimmed(_ attributed: AttributedString) -> AttributedString {
        var start = attributed.startIndex
        while start < attributed.endIndex, attributed.characters[start].isWhitespace {
            start = attributed.index(afterCharacter: start)
        }
        var end = attributed.endIndex
        while end > start {
            let previous = attributed.index(beforeCharacter: end)
            if attributed.characters[previous].isWhitespace { end = previous } else { break }
        }
        return AttributedString(attributed[start..<end])
    }

    private static func decodeEntities(_ input: String) -> String {
        var s = input
        // `&amp;` is decoded last so "&amp;lt;" yields the literal "&lt;", not "<".
        // (Dictionary order is unspecified, so use an ordered array.)
        let named: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&"),
        ]
        for (entity, value) in named {
            s = s.replacingOccurrences(of: entity, with: value)
        }
        // Numeric decimal entities like &#233;
        while let range = s.range(of: "&#[0-9]+;", options: .regularExpression) {
            let digits = s[range].dropFirst(2).dropLast()
            if let code = UInt32(digits), let scalar = Unicode.Scalar(code) {
                s.replaceSubrange(range, with: String(scalar))
            } else {
                s.replaceSubrange(range, with: "")
            }
        }
        // Numeric hex entities like &#x1F600;
        while let range = s.range(of: "&#[xX][0-9A-Fa-f]+;", options: .regularExpression) {
            let hex = s[range].dropFirst(3).dropLast()
            if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                s.replaceSubrange(range, with: String(scalar))
            } else {
                s.replaceSubrange(range, with: "")
            }
        }
        return s
    }
}
