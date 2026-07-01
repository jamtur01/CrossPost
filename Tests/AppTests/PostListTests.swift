import XCTest
@testable import CrossPost

/// `PostList` backs thread and profile views. Unlike the timeline, its optimistic
/// like/repost must adjust the visible counts, and bookmark/pin must update its own
/// rows (not the panel's separate timeline array).
@MainActor
final class PostListTests: XCTestCase {
    override func tearDown() {
        let store = AccountStore()
        store.mastodonInstanceURL = ""
        store.blueskyHandle = ""
        super.tearDown()
    }

    private func makeModel(_ fake: FakeFeedService) -> FeedPanelModel {
        let store = AccountStore()
        store.mastodonInstanceURL = "https://h.io"
        store.mastodonToken = "tok"
        store.blueskyHandle = "me.bsky.social"
        store.blueskyAppPassword = "pw"
        return FeedPanelModel(target: .bluesky, store: store) { _, _ in fake }
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool, timeout: TimeInterval = 2,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() >= deadline { XCTFail("condition not met within timeout", file: file, line: line); return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func testToggleLikeAdjustsCountOptimisticallyAndKeepsItAfterReconcile() async {
        let fake = FakeFeedService()
        let list = PostList(panel: makeModel(fake))
        var post = TestFactory.feedPost(target: .bluesky)
        post.likeCount = 5
        list.posts = [post]

        list.toggleLike(post)
        XCTAssertTrue(list.posts[0].isLiked)            // optimistic, synchronous
        XCTAssertEqual(list.posts[0].likeCount, 6)

        await waitUntil { list.posts[0].likeRecordURI != nil }   // service reconciled
        XCTAssertEqual(list.posts[0].likeCount, 6)               // count not lost
    }

    func testUnlikeDecrementsCountNotBelowZero() async {
        let fake = FakeFeedService()
        let list = PostList(panel: makeModel(fake))
        var post = TestFactory.feedPost(target: .bluesky)
        post.isLiked = true
        post.likeCount = 0     // inconsistent server state; must not go negative
        list.posts = [post]

        list.toggleLike(post)
        XCTAssertFalse(list.posts[0].isLiked)
        XCTAssertEqual(list.posts[0].likeCount, 0)
    }

    func testToggleRepostAdjustsCountAndReconciles() async {
        let fake = FakeFeedService()
        let list = PostList(panel: makeModel(fake))
        var post = TestFactory.feedPost(target: .bluesky)
        post.repostCount = 2
        list.posts = [post]

        list.toggleRepost(post)
        XCTAssertTrue(list.posts[0].isReposted)         // optimistic, synchronous
        XCTAssertEqual(list.posts[0].repostCount, 3)

        await waitUntil { list.posts[0].repostRecordURI != nil }   // reconciled
        XCTAssertEqual(list.posts[0].repostCount, 3)
    }

    func testLikeFailureRollsBackOptimisticChange() async {
        let fake = FakeFeedService()
        fake.failLike = true
        let list = PostList(panel: makeModel(fake))
        var post = TestFactory.feedPost(target: .bluesky)
        post.likeCount = 5
        list.posts = [post]

        list.toggleLike(post)
        XCTAssertTrue(list.posts[0].isLiked)            // optimistic
        XCTAssertEqual(list.posts[0].likeCount, 6)

        await waitUntil { !list.posts[0].isLiked }      // rolled back on failure
        XCTAssertEqual(list.posts[0].likeCount, 5)      // count restored
    }

    func testSetPinnedUpdatesItsOwnRow() async {
        let fake = FakeFeedService()
        let list = PostList(panel: makeModel(fake))
        let post = TestFactory.feedPost(target: .bluesky)
        list.posts = [post]

        list.setPinned(true, on: post)
        XCTAssertTrue(list.posts[0].isPinned)           // optimistic

        await waitUntil { fake.pinSetCalls == [true] }
        XCTAssertTrue(list.posts[0].isPinned)           // not rolled back
    }

    func testDeleteRemovesRowAndStaysRemoved() async {
        let fake = FakeFeedService()
        let list = PostList(panel: makeModel(fake))
        let posts = ["a", "b"].map { TestFactory.feedPost(target: .bluesky, id: $0) }
        list.posts = posts

        list.delete(posts[0])
        XCTAssertEqual(list.posts.map(\.id), ["b"])     // optimistic removal

        await waitUntil { fake.deletedIDs.contains("a") }
        XCTAssertEqual(list.posts.map(\.id), ["b"])
    }

    func testDeleteFailureReInsertsRow() async {
        let fake = FakeFeedService()
        fake.failDelete = true
        let list = PostList(panel: makeModel(fake))
        let posts = ["a", "b", "c"].map { TestFactory.feedPost(target: .bluesky, id: $0) }
        list.posts = posts

        list.delete(posts[1])
        XCTAssertEqual(list.posts.map(\.id), ["a", "c"])    // optimistic removal

        await waitUntil { list.posts.count == 3 }           // re-inserted on failure
        XCTAssertEqual(list.posts.map(\.id), ["a", "b", "c"])
    }

    func testSetBookmarkedUpdatesItsOwnRow() async {
        let fake = FakeFeedService()
        let list = PostList(panel: makeModel(fake))
        let post = TestFactory.feedPost(target: .bluesky)
        list.posts = [post]

        list.setBookmarked(true, on: post)
        XCTAssertTrue(list.posts[0].isBookmarked)               // optimistic, synchronous

        await waitUntil { fake.bookmarkSetCalls == [true] }      // reconcile ran
        XCTAssertTrue(list.posts[0].isBookmarked)               // not rolled back
    }
}
