@testable import CrossPost
import XCTest

@MainActor
final class PostRevealsTests: XCTestCase {
    func testPlainPostShowsEverything() {
        let reveals = PostReveals()
        let post = TestFactory.feedPost(spoilerText: " \n")
        XCTAssertTrue(reveals.showsContent(of: post))
        XCTAssertTrue(reveals.showsMedia(of: post))
    }

    func testContentWarningHidesUntilToggledAndCanBeHiddenAgain() {
        let reveals = PostReveals()
        let post = TestFactory.feedPost(spoilerText: "spoilers")
        XCTAssertFalse(reveals.showsContent(of: post))
        reveals.toggleContent(of: post)
        XCTAssertTrue(reveals.showsContent(of: post))
        reveals.toggleContent(of: post)
        XCTAssertFalse(reveals.showsContent(of: post))
    }

    /// Mastodon's behavior: opening the warning shows the text, not the media.
    func testOpeningWarningLeavesSensitiveMediaCovered() {
        let reveals = PostReveals()
        let post = TestFactory.feedPost(spoilerText: "spoilers", isSensitive: true)
        reveals.toggleContent(of: post)
        XCTAssertTrue(reveals.showsContent(of: post))
        XCTAssertFalse(reveals.showsMedia(of: post))
        reveals.toggleMedia(of: post)
        XCTAssertTrue(reveals.showsMedia(of: post))
    }

    func testRevealIsPerPostAndSharedWithBoostRows() {
        let reveals = PostReveals()
        let post = TestFactory.feedPost(id: "mastodon:1", spoilerText: "cw", isSensitive: true)
        let other = TestFactory.feedPost(id: "mastodon:2", spoilerText: "cw", isSensitive: true)
        let boost = TestFactory.boost(of: post, id: "mastodon:boost-1")
        reveals.toggleContent(of: boost)
        reveals.toggleMedia(of: post)
        XCTAssertTrue(reveals.showsContent(of: post))
        XCTAssertTrue(reveals.showsMedia(of: boost))
        XCTAssertFalse(reveals.showsContent(of: other))
        XCTAssertFalse(reveals.showsMedia(of: other))
    }
}
