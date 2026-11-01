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

    /// A quote carries the quoted post's warning, so quoting can't bypass it, and
    /// opening the quoted post in its own thread opens the quote too.
    func testQuoteIsCoveredAndSharesTheQuotedPostsReveal() {
        let reveals = PostReveals()
        let quoted = TestFactory.feedPost(id: "7", spoilerText: "cw", isSensitive: true)
        let quote = QuotedPost(id: "mastodon:7", authorName: "A", authorHandle: "@a", avatarURL: nil,
                               text: "hidden", imageURL: nil, webURL: nil,
                               spoilerText: "cw", isSensitive: true)
        XCTAssertFalse(reveals.showsContent(of: quote))
        XCTAssertFalse(reveals.showsMedia(of: quote))
        reveals.toggleContent(of: quoted)
        XCTAssertTrue(reveals.showsContent(of: quote))
        XCTAssertFalse(reveals.showsMedia(of: quote))
    }
}
