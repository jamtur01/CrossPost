import Foundation

public enum HTMLRenderer {
    /// Convert Mastodon's limited HTML into clean plain text:
    /// `</p>` → blank line, `<br>` → newline, other tags stripped, entities decoded.
    public static func render(_ html: String) -> String {
        var s = html
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
