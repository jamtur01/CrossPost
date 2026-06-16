import XCTest
@testable import CrossPost

final class NavigationTests: XCTestCase {
    func testProfileRefDerivedFromPost() {
        let post = TestFactory.feedPost(
            target: .bluesky, authorName: "Bob", authorHandle: "@bob.bsky.social",
            authorID: "bob.bsky.social")
        let ref = post.profileRef()
        XCTAssertEqual(ref.id, "bob.bsky.social")
        XCTAssertEqual(ref.handle, "@bob.bsky.social")
        XCTAssertEqual(ref.name, "Bob")
        XCTAssertFalse(ref.isMe)
    }

    func testFeedRouteIDsAreStableAndDistinct() {
        let post = TestFactory.feedPost()
        let ref = post.profileRef()
        XCTAssertEqual(FeedRoute.thread(post).id, "thread:\(post.id)")
        XCTAssertEqual(FeedRoute.profile(ref).id, "profile:\(ref.id):false")
        XCTAssertNotEqual(FeedRoute.thread(post).id, FeedRoute.profile(ref).id)
    }

    func testSavedRouteIDsAreStableAndDistinct() {
        XCTAssertEqual(FeedRoute.saved(.bookmarks).id, "saved:bookmarks")
        XCTAssertEqual(FeedRoute.saved(.likes).id, "saved:likes")
        XCTAssertNotEqual(FeedRoute.saved(.bookmarks).id, FeedRoute.saved(.likes).id)
    }

    func testSavedKindTitles() {
        XCTAssertEqual(SavedKind.bookmarks.title, "Bookmarks")
        XCTAssertEqual(SavedKind.likes.title, "Likes")
    }
}
