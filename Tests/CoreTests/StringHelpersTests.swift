import XCTest
@testable import CrossPost

final class StringHelpersTests: XCTestCase {
    // MARK: displayOrHandle — the "blank display name → blank UI" trap, used at 12 sites.

    func testDisplayNameUsedWhenPresent() {
        XCTAssertEqual(displayOrHandle("Ada Lovelace", "@ada"), "Ada Lovelace")
    }

    func testNilDisplayNameFallsBackToHandle() {
        XCTAssertEqual(displayOrHandle(nil, "@ada"), "@ada")
    }

    func testEmptyDisplayNameFallsBackToHandle() {
        XCTAssertEqual(displayOrHandle("", "@ada"), "@ada")
    }

    func testWhitespaceOnlyDisplayNameFallsBackToHandle() {
        // Servers hand back " " / "\n" for "no name"; those must not surface as blank UI.
        XCTAssertEqual(displayOrHandle("  ", "@ada"), "@ada")
        XCTAssertEqual(displayOrHandle("\n\t", "@ada"), "@ada")
    }

    // MARK: String.nilIfBlank — blank → nil, otherwise the ORIGINAL (untrimmed).

    func testNonBlankReturnsSelf() {
        XCTAssertEqual("x".nilIfBlank, "x")
    }

    func testEmptyIsNil() {
        XCTAssertNil("".nilIfBlank)
    }

    func testWhitespaceAndNewlinesAreNil() {
        XCTAssertNil("  \n".nilIfBlank)
    }

    func testNonBlankKeepsSurroundingWhitespace() {
        // Only blankness is tested for; a non-blank value is returned verbatim, not trimmed.
        XCTAssertEqual(" x ".nilIfBlank, " x ")
    }

    // MARK: BlueskyURL.rkey — last path component, or nil when there's nothing to split.

    func testRkeyIsLastPathComponent() {
        XCTAssertEqual(BlueskyURL.rkey(from: "at://did:plc:abc/app.bsky.feed.post/3kxyz"), "3kxyz")
    }

    func testRkeyOfEmptyIsNil() {
        XCTAssertNil(BlueskyURL.rkey(from: ""))
    }

    func testRkeyOfSlashesOnlyIsNil() {
        XCTAssertNil(BlueskyURL.rkey(from: "///"))
    }
}
