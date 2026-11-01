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
    /// opening the quoted post in its own thread opens the quote too, on both networks.
    func testQuoteIsCoveredAndSharesTheQuotedPostsReveal() {
        let mastodon = TestFactory.feedPost(id: "7", spoilerText: "cw", isSensitive: true)
        let bluesky = TestFactory.feedPost(target: .bluesky, id: "did:plc:a/app.bsky.feed.post/7",
                                           spoilerText: "Content warning", isSensitive: true)
        // Each quote's id as the network's mapping gives it.
        for (quoted, quoteID) in [(mastodon, "mastodon:7"), (bluesky, "at://did:plc:a/app.bsky.feed.post/7")] {
            let reveals = PostReveals()
            let quote = QuotedPost(id: quoteID, authorName: "A", authorHandle: "@a", avatarURL: nil,
                                   text: "hidden", imageURL: nil, webURL: nil,
                                   spoilerText: quoted.spoilerText, isSensitive: true)
            XCTAssertFalse(reveals.showsContent(of: quote), quoteID)
            XCTAssertFalse(reveals.showsMedia(of: quote), quoteID)
            reveals.toggleContent(of: quoted)
            XCTAssertTrue(reveals.showsContent(of: quote), quoteID)
            XCTAssertFalse(reveals.showsMedia(of: quote), quoteID)
            reveals.toggleMedia(of: quote)
            XCTAssertTrue(reveals.showsMedia(of: quoted), quoteID)
        }
    }
}
