@testable import CrossPost
import XCTest

final class CustomEmojiTests: XCTestCase {
    private let verified = URL(string: "https://e.io/verified.png")!
    private let python = URL(string: "https://e.io/python.png")!

    private func texts(_ segments: [CustomEmoji.Segment]) -> [String] {
        segments.map { segment in
            switch segment {
            case let .text(run): String(run.characters)
            case let .emoji(shortcode, _): "<\(shortcode)>"
            }
        }
    }

    func testNoEmojiMapKeepsTextWhole() {
        let segments = CustomEmoji.segments(in: AttributedString("Beta.NYC :verified:"), emojis: [:])
        XCTAssertEqual(texts(segments), ["Beta.NYC :verified:"])
    }

    func testSplitsKnownShortcodeFromName() {
        let segments = CustomEmoji.segments(
            in: AttributedString("Beta.NYC :verified:"), emojis: ["verified": verified]
        )
        XCTAssertEqual(segments, [
            .text(AttributedString("Beta.NYC ")),
            .emoji(shortcode: "verified", url: verified)
        ])
    }

    func testUnknownShortcodeStaysText() {
        let segments = CustomEmoji.segments(
            in: AttributedString("hi :nope: and :python: done"), emojis: ["python": python]
        )
        XCTAssertEqual(texts(segments), ["hi :nope: and ", "<python>", " done"])
    }

    func testAdjacentShortcodes() {
        let segments = CustomEmoji.segments(
            in: AttributedString(":python::verified:"), emojis: ["python": python, "verified": verified]
        )
        XCTAssertEqual(texts(segments), ["<python>", "<verified>"])
    }

    func testStrayColonsDoNotSwallowALaterShortcode() {
        let segments = CustomEmoji.segments(
            in: AttributedString("at 10:30 :python:"), emojis: ["python": python]
        )
        XCTAssertEqual(texts(segments), ["at 10:30 ", "<python>"])
    }

    func testUnclosedColonStaysText() {
        let segments = CustomEmoji.segments(in: AttributedString("ratio 3:1"), emojis: ["python": python])
        XCTAssertEqual(texts(segments), ["ratio 3:1"])
    }

    func testTextRunsKeepTheirAttributes() throws {
        var text = AttributedString("see link :python:")
        let link = try XCTUnwrap(URL(string: "https://example.com"))
        let range = try XCTUnwrap(text.range(of: "link"))
        text[range].link = link

        let segments = CustomEmoji.segments(in: text, emojis: ["python": python])
        guard case let .text(run) = segments.first else { return XCTFail("expected leading text") }
        XCTAssertEqual(run.runs.compactMap(\.link), [link])
    }
}
