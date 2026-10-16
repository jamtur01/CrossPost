import Foundation

enum HTMLRenderer {
    /// Convert Mastodon's limited HTML into an AttributedString: `</p>` → blank
    /// line, `<br>` → newline, `<a href>` → a link run (visible label as text,
    /// href as `.link`), other tags stripped, entities decoded.
    static func renderAttributed(_ html: String) -> AttributedString {
        var html = html
        // Match the closing/self-closing tags tolerant of attributes and whitespace
        // (e.g. a federated instance's `<br class="…">`), which a literal match misses.
        html = html.replacingOccurrences(of: "</p\\s*>", with: "\n\n",
                                         options: [.regularExpression, .caseInsensitive])
        html = html.replacingOccurrences(of: "<br[^>]*>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])

        var result = AttributedString()
        let nsInput = html as NSString
        var cursor = 0
        for match in anchorMatches(in: html) {
            if match.range.location > cursor {
                let preLength = match.range.location - cursor
                let pre = nsInput.substring(with: NSRange(location: cursor, length: preLength))
                result.append(AttributedString(plainText(pre)))
            }
            result.append(anchorPiece(match, in: html))
            cursor = match.range.location + match.range.length
        }
        if cursor < nsInput.length {
            result.append(AttributedString(plainText(nsInput.substring(from: cursor))))
        }
        return trimmed(result)
    }

    /// Compiled once: this runs for every Mastodon post mapped, and compiling an
    /// NSRegularExpression costs far more than executing it.
    private static let anchorRegex = try? NSRegularExpression(
        pattern: #"<a\b[^>]*\bhref\s*=\s*(['"])(.*?)\1[^>]*>(.*?)</a>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static func anchorMatches(in input: String) -> [NSTextCheckingResult] {
        guard let regex = anchorRegex else { return [] }
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
        if let url = URL(string: href), WebLink.isOpenable(url) {
            piece.link = url
        }
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
            if attributed.characters[previous].isWhitespace {
                end = previous
            } else {
                break
            }
        }
        return AttributedString(attributed[start ..< end])
    }

    private static let namedEntities: [(String, String)] = [
        ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
        ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")
    ]

    /// Decode entities in one left-to-right pass: each `&` is inspected once and
    /// the decoded (or literal) text appended, so already-decoded output is never
    /// re-scanned. That keeps `&amp;#39;` literal (`&#39;`, not `'`) and the whole
    /// pass O(n), where the old repeated `range(of:)` loops were O(n²).
    private static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var out = ""
        out.reserveCapacity(input.count)
        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            guard character == "&" else {
                out.append(character)
                index = input.index(after: index)
                continue
            }
            if let (decoded, next) = decodeEntity(in: input, at: index) {
                out.append(decoded)
                index = next
            } else {
                out.append("&")
                index = input.index(after: index)
            }
        }
        return out
    }

    /// The entity starting at `start` (an `&`): its decoded text and the index
    /// just past it, or nil when what follows isn't a recognized entity. An
    /// invalid numeric scalar (e.g. a lone surrogate) is consumed but decodes
    /// to nothing, matching the previous behavior.
    private static func decodeEntity(in text: String, at start: String.Index)
        -> (String, String.Index)? {
        for (entity, value) in namedEntities where text[start...].hasPrefix(entity) {
            return (value, text.index(start, offsetBy: entity.count))
        }
        var cursor = text.index(after: start)
        guard cursor < text.endIndex, text[cursor] == "#" else { return nil }
        cursor = text.index(after: cursor)
        let isHex = cursor < text.endIndex && (text[cursor] == "x" || text[cursor] == "X")
        if isHex {
            cursor = text.index(after: cursor)
        }
        let digitsStart = cursor
        while cursor < text.endIndex, isEntityDigit(text[cursor], hex: isHex) {
            cursor = text.index(after: cursor)
        }
        guard cursor > digitsStart, cursor < text.endIndex, text[cursor] == ";" else { return nil }
        let end = text.index(after: cursor)
        guard let code = UInt32(text[digitsStart ..< cursor], radix: isHex ? 16 : 10),
              let scalar = Unicode.Scalar(code) else { return ("", end) }
        return (String(scalar), end)
    }

    /// ASCII-only on purpose: `Character.isHexDigit` also accepts fullwidth
    /// compatibility forms, which UInt32(_:radix:) would then fail to parse.
    private static func isEntityDigit(_ character: Character, hex: Bool) -> Bool {
        if ("0" ... "9").contains(character) {
            return true
        }
        return hex && (("a" ... "f").contains(character) || ("A" ... "F").contains(character))
    }
}
