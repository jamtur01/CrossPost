import XCTest
@testable import CrossPost

final class HTMLRendererTests: XCTestCase {
    func testStripsTags() {
        XCTAssertEqual(HTMLRenderer.render("<p>hello <span>world</span></p>"), "hello world")
    }

    func testParagraphsBecomeBlankLineSeparated() {
        XCTAssertEqual(HTMLRenderer.render("<p>one</p><p>two</p>"), "one\n\ntwo")
    }

    func testBrBecomesNewline() {
        XCTAssertEqual(HTMLRenderer.render("a<br>b<br/>c"), "a\nb\nc")
    }

    func testDecodesEntities() {
        XCTAssertEqual(HTMLRenderer.render("Ben &amp; Jerry &lt;3 &#39;x&#39; &quot;y&quot;"),
                       "Ben & Jerry <3 'x' \"y\"")
    }

    func testDecodesNumericEntity() {
        XCTAssertEqual(HTMLRenderer.render("caf&#233;"), "café")
    }

    func testDecodesHexEntity() {
        XCTAssertEqual(HTMLRenderer.render("smile &#x1F600; and caf&#xE9;"), "smile 😀 and café")
    }

    func testLinkRendersAsItsText() {
        XCTAssertEqual(HTMLRenderer.render(#"see <a href="https://x.com">x.com</a>"#), "see x.com")
    }

    func testTrimsTrailingWhitespace() {
        XCTAssertEqual(HTMLRenderer.render("<p>hi</p>"), "hi")
    }

    func testEmptyAndPlain() {
        XCTAssertEqual(HTMLRenderer.render(""), "")
        XCTAssertEqual(HTMLRenderer.render("plain text"), "plain text")
    }
}
