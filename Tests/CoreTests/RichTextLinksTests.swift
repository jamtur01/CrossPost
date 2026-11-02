@testable import CrossPost
import XCTest

final class RichTextLinksTests: XCTestCase {
    private func span(_ start: Int, _ end: Int, _ url: String) -> RichTextLinks.Span {
        RichTextLinks.Span(byteStart: start, byteEnd: end, url: URL(string: url)!)
    }

    func testLinksAnASCIIRange() {
        // "hi @bob there": "@bob" is bytes [3, 7).
        let result = RichTextLinks.attributed(
            "hi @bob there",
            spans: [span(3, 7, "https://bsky.app/profile/did:plc:bob")]
        )
        XCTAssertEqual(result.linkRuns.map(\.text), ["@bob"])
        XCTAssertEqual(result.linkRuns.first?.url, URL(string: "https://bsky.app/profile/did:plc:bob"))
    }

    func testByteOffsetsAccountForMultibyteCharacters() {
        // "🎉 @bob": the emoji is 4 UTF-8 bytes + a space, so "@bob" is bytes [5, 9).
        let result = RichTextLinks.attributed("🎉 @bob", spans: [span(5, 9, "https://example.com")])
        XCTAssertEqual(result.linkRuns.map(\.text), ["@bob"])
    }

    func testAppliesMultipleSpans() {
        // "@a #b": "@a" is [0,2), "#b" is [3,5).
        let result = RichTextLinks.attributed("@a #b", spans: [
            span(0, 2, "https://bsky.app/profile/a"),
            span(3, 5, "https://bsky.app/hashtag/b")
        ])
        XCTAssertEqual(result.linkRuns.map(\.text), ["@a", "#b"])
    }

    func testOutOfBoundsRangeIsSkipped() {
        let result = RichTextLinks.attributed("hi", spans: [span(0, 99, "https://example.com")])
        XCTAssertTrue(result.linkRuns.isEmpty)
    }

    func testRangeLandingMidCharacterIsSkipped() {
        // "🎉" is one 4-byte scalar; bytes [0, 2) split it and must be ignored.
        let result = RichTextLinks.attributed("🎉", spans: [span(0, 2, "https://example.com")])
        XCTAssertTrue(result.linkRuns.isEmpty)
    }

    func testNoSpansLeavesPlainText() {
        let result = RichTextLinks.attributed("just words", spans: [])
        XCTAssertTrue(result.linkRuns.isEmpty)
        XCTAssertEqual(String(result.characters), "just words")
    }

    func testNonWebSchemeSpanIsNotLinked() {
        // A facet pointing at a non-http(s) scheme must not become tappable.
        let result = RichTextLinks.attributed("hi @bob there", spans: [span(3, 7, "file:///etc/passwd")])
        XCTAssertTrue(result.linkRuns.isEmpty)
        XCTAssertEqual(String(result.characters), "hi @bob there")
    }
}
