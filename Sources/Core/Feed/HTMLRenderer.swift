import Foundation

public enum HTMLRenderer {
    /// Convert Mastodon's limited HTML into clean plain text:
    /// `</p>` → blank line, `<br>` → newline, other tags stripped, entities decoded.
    public static func render(_ html: String) -> String {
        var s = html
        s = replaceAnchors(s)
        // Block/line breaks first, before stripping tags.
        s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        // Strip all remaining tags.
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceAnchors(_ input: String) -> String {
        let pattern = #"<a\b[^>]*\bhref\s*=\s*(['"])(.*?)\1[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return input
        }

        var output = input
        let nsInput = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: nsInput.length))
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let hrefRange = Range(match.range(at: 2), in: input),
                  let labelRange = Range(match.range(at: 3), in: input),
                  let fullRange = Range(match.range(at: 0), in: output)
            else { continue }

            let href = decodeEntities(String(input[hrefRange]))
            let label = renderAnchorLabel(String(input[labelRange]))
            let replacement: String
            if label.isEmpty || label == href {
                replacement = href
            } else {
                replacement = "\(label) (\(href))"
            }
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
    }

    private static func renderAnchorLabel(_ html: String) -> String {
        decodeEntities(
            html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ input: String) -> String {
        var s = input
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
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
