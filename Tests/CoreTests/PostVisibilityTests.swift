import XCTest
@testable import CrossPost

final class PostVisibilityTests: XCTestCase {
    func testInitFromMastodonStringsMapsEachLevel() {
        XCTAssertEqual(PostVisibility(mastodon: "public"), .public)
        XCTAssertEqual(PostVisibility(mastodon: "unlisted"), .unlisted)
        XCTAssertEqual(PostVisibility(mastodon: "private"), .private)
        XCTAssertEqual(PostVisibility(mastodon: "direct"), .direct)
    }

    func testInitFromNilOrUnknownStringIsNil() {
        XCTAssertNil(PostVisibility(mastodon: nil))
        XCTAssertNil(PostVisibility(mastodon: ""))
        XCTAssertNil(PostVisibility(mastodon: "bogus"))
    }

    func testRawValuesMatchMastodonAPIStrings() {
        // The adapter maps straight onto the SDK's string-backed type, so these
        // must stay identical to Mastodon's API values.
        XCTAssertEqual(Set(PostVisibility.allCases.map(\.rawValue)),
                       ["public", "unlisted", "private", "direct"])
    }
}
