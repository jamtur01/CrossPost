import XCTest
@testable import CrossPost

final class TargetLimitsTests: XCTestCase {
    func testDefaultLimits() {
        let limits = TargetLimits()
        XCTAssertEqual(limits.maxGraphemes[.bluesky], 300)
        XCTAssertEqual(limits.maxGraphemes[.mastodon], 500)
        XCTAssertEqual(limits.maxImages[.mastodon], 4)
        XCTAssertEqual(limits.maxImages[.bluesky], 4)
    }

    func testCustomMastodonMaxOnlyAffectsMastodon() {
        let limits = TargetLimits(mastodonMax: 1000)
        XCTAssertEqual(limits.maxGraphemes[.mastodon], 1000)
        XCTAssertEqual(limits.maxGraphemes[.bluesky], 300)
    }
}
