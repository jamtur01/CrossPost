import XCTest
@testable import CrossPost

final class HTMLRendererTests: XCTestCase {
    private func plain(_ html: String) -> String {
        String(HTMLRenderer.renderAttributed(html).characters)
    }

    private func links(_ html: String) -> [URL] {
        HTMLRenderer.renderAttributed(html).runs.compactMap(\.link)
    }

    func testStripsTags() {
        XCTAssertEqual(plain("<p>hello <span>world</span></p>"), "hello world")
    }

    func testParagraphsBecomeBlankLineSeparated() {
        XCTAssertEqual(plain("<p>one</p><p>two</p>"), "one\n\ntwo")
    }

    func testBrBecomesNewline() {
        XCTAssertEqual(plain("a<br>b<br/>c"), "a\nb\nc")
    }

    func testBrAndPWithAttributesBecomeBreaks() {
        // A federated instance may emit <br>/<p> with attributes; these must still break.
        XCTAssertEqual(plain("a<br class=\"x\">b"), "a\nb")
        XCTAssertEqual(plain("<p dir=\"ltr\">one</p><p>two</p>"), "one\n\ntwo")
        XCTAssertEqual(plain("a<BR />b"), "a\nb")
    }

    func testDecodesEntities() {
        XCTAssertEqual(plain("Ben &amp; Jerry &lt;3 &#39;x&#39; &quot;y&quot;"),
                       "Ben & Jerry <3 'x' \"y\"")
    }

    func testDoubleEscapedAmpersandDecodesToLiteralEntity() {
        // "&amp;lt;" is the escaping of the literal text "&lt;", not of "<".
        XCTAssertEqual(plain("&amp;lt;"), "&lt;")
        XCTAssertEqual(plain("&amp;amp;"), "&amp;")
        XCTAssertEqual(plain("a &amp; b &lt; c"), "a & b < c")
    }

    func testDecodesNumericEntity() {
        XCTAssertEqual(plain("caf&#233;"), "café")
    }

    func testDecodesHexEntity() {
        XCTAssertEqual(plain("smile &#x1F600; and caf&#xE9;"), "smile 😀 and café")
    }

    func testEscapedNumericEntityStaysLiteral() {
        // "&amp;#39;" escapes the literal text "&#39;" — decoding the numeric
        // form afterwards would double-decode it to "'".
        XCTAssertEqual(plain("&amp;#39;"), "&#39;")
        XCTAssertEqual(plain("&amp;#x27;"), "&#x27;")
    }

    func testInvalidNumericScalarIsDropped() {
        // 55296 (0xD800) is a lone surrogate — not a valid Unicode scalar.
        XCTAssertEqual(plain("a&#55296;b"), "ab")
        XCTAssertEqual(plain("a&#xD800;b"), "ab")
    }

    func testUnterminatedOrUnknownEntitiesStayLiteral() {
        XCTAssertEqual(plain("AT&T"), "AT&T")
        XCTAssertEqual(plain("&#39x"), "&#39x")
        XCTAssertEqual(plain("&unknown;"), "&unknown;")
    }

    func testManyEntitiesDecodeCorrectly() {
        let repeats = 500
        let html = String(repeating: "&lt;&#39;&amp;&#x1F600;", count: repeats)
        XCTAssertEqual(plain(html), String(repeating: "<'&😀", count: repeats))
    }

    func testAnchorBecomesClickableLinkWithoutShowingURL() {
        let html = #"see <a href="https://x.com">x.com</a>"#
        XCTAssertEqual(plain(html), "see x.com")
        XCTAssertEqual(links(html), [URL(string: "https://x.com")!])
    }

    func testMentionAnchorLabelIsTheLink() {
        let html = #"<a href="https://hachyderm.io/@kartar" class="u-url mention">@<span>kartar</span></a>"#
        XCTAssertEqual(plain(html), "@kartar")
        XCTAssertEqual(links(html), [URL(string: "https://hachyderm.io/@kartar")!])
    }

    func testAnchorLabelCanContainNestedTags() {
        let html = #"<a class="u-url" href="https://example.com"><span>Example</span></a>"#
        XCTAssertEqual(plain(html), "Example")
        XCTAssertEqual(links(html), [URL(string: "https://example.com")!])
    }

    func testNonWebSchemeAnchorRendersLabelButNoLink() {
        // A malicious post can't smuggle a file:// link past the renderer.
        let html = #"<a href="file:///etc/passwd">click me</a>"#
        XCTAssertEqual(plain(html), "click me")
        XCTAssertTrue(links(html).isEmpty)
    }

    func testPlainTextHasNoLinks() {
        XCTAssertTrue(links("just words").isEmpty)
    }

    func testTrimsTrailingWhitespace() {
        XCTAssertEqual(plain("<p>hi</p>"), "hi")
    }

    func testEmptyAndPlain() {
        XCTAssertEqual(plain(""), "")
        XCTAssertEqual(plain("plain text"), "plain text")
    }
}
