import Foundation

/// Applies `.link` attributes to UTF-8 byte ranges of a string — the encoding
/// Bluesky richtext facets use (start inclusive, end exclusive, zero-indexed).
/// Ranges that are out of bounds or land mid-character are skipped, not fatal.
public enum RichTextLinks {
    public struct Span: Sendable {
        public let byteStart: Int
        public let byteEnd: Int
        public let url: URL
        public init(byteStart: Int, byteEnd: Int, url: URL) {
            self.byteStart = byteStart
            self.byteEnd = byteEnd
            self.url = url
        }
    }

    public static func attributed(_ text: String, spans: [Span]) -> AttributedString {
        var result = AttributedString(text)
        for span in spans {
            guard WebLink.isOpenable(span.url),
                  let range = range(of: span, in: text, of: result) else { continue }
            result[range].link = span.url
        }
        return result
    }

    private static func range(of span: Span, in text: String,
                              of attributed: AttributedString) -> Range<AttributedString.Index>? {
        let utf8 = text.utf8
        guard span.byteStart >= 0, span.byteStart < span.byteEnd, span.byteEnd <= utf8.count,
              let lowUTF8 = utf8.index(utf8.startIndex, offsetBy: span.byteStart, limitedBy: utf8.endIndex),
              let highUTF8 = utf8.index(utf8.startIndex, offsetBy: span.byteEnd, limitedBy: utf8.endIndex),
              let low = lowUTF8.samePosition(in: text),
              let high = highUTF8.samePosition(in: text),
              let attrLow = AttributedString.Index(low, within: attributed),
              let attrHigh = AttributedString.Index(high, within: attributed)
        else { return nil }
        return attrLow..<attrHigh
    }
}
