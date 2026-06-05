import XCTest
import SwiftUI
@testable import CrossPost

final class RichTextTests: XCTestCase {
    private let accent = Color.red

    private func links(_ s: AttributedString) -> [(text: String, url: URL)] {
        s.runs.compactMap { run in
            guard let url = run.link else { return nil }
            return (String(s[run.range].characters), url)
        }
    }

    private func colored(_ s: AttributedString) -> [String] {
        s.runs.compactMap { run in
            run.foregroundColor == accent ? String(s[run.range].characters) : nil
        }
    }

    func testColorsBareMention() {
        let styled = RichText.styled(AttributedString("hi @bob there"), accent: accent)
        XCTAssertEqual(colored(styled), ["@bob"])
        XCTAssertTrue(links(styled).isEmpty)
    }

    func testColorsHashtag() {
        let styled = RichText.styled(AttributedString("love #swift today"), accent: accent)
        XCTAssertEqual(colored(styled), ["#swift"])
    }

    func testDetectsBareURLAsColoredLink() {
        let styled = RichText.styled(AttributedString("see https://x.com now"), accent: accent)
        let found = links(styled)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.text, "https://x.com")
        XCTAssertEqual(found.first?.url, URL(string: "https://x.com"))
        XCTAssertEqual(colored(styled), ["https://x.com"])
    }

    func testPreservesExistingLinkWithoutDuplicating() {
        var input = AttributedString("see ")
        var anchor = AttributedString("example.com")
        anchor.link = URL(string: "https://example.com")
        input.append(anchor)

        let styled = RichText.styled(input, accent: accent)
        let found = links(styled)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.text, "example.com")
        XCTAssertEqual(found.first?.url, URL(string: "https://example.com"))
        XCTAssertEqual(colored(styled), ["example.com"])
    }

    /// End-to-end regression: a Mastodon mention HTML must render as a single
    /// clickable link showing only the handle, never "@name (url)".
    func testMastodonMentionRendersAsSingleLink() {
        let html = #"<a href="https://hachyderm.io/@kartar" class="u-url mention">@<span>kartar</span></a>"#
        let styled = RichText.styled(HTMLRenderer.renderAttributed(html), accent: accent)

        XCTAssertEqual(String(styled.characters), "@kartar")
        let found = links(styled)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.text, "@kartar")
        XCTAssertEqual(found.first?.url, URL(string: "https://hachyderm.io/@kartar"))
    }

    func testPlainTextGetsNoLinksOrColor() {
        let styled = RichText.styled(AttributedString("just some words"), accent: accent)
        XCTAssertTrue(links(styled).isEmpty)
        XCTAssertTrue(colored(styled).isEmpty)
    }
}
