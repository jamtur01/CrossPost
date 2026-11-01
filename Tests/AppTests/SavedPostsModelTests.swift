@testable import CrossPost
import XCTest

/// Bookmarks and Likes load a page each time the end of the list comes into view
/// (`loadMore()`), until the network reports no more.
@MainActor
final class SavedPostsModelTests: FeedPanelTestCase {
    private func bookmarked(_ ids: [String]) -> [FeedPost] {
        ids.map { id in
            var post = TestFactory.feedPost(id: id)
            post.isBookmarked = true
            return post
        }
    }

    func testPagesUntilTheEndThenStopsRequesting() async {
        let fake = FakeFeedService()
        fake.feed = bookmarked(["a", "b", "c", "d", "e"])
        fake.savedPageSize = 2
        let model = SavedPostsModel(panel: makeModel(fake), kind: .bookmarks)

        await model.loadMore()
        XCTAssertEqual(model.list.posts.map(\.id), ["a", "b"])
        XCTAssertTrue(model.wantsMore)

        await model.loadMore()
        await model.loadMore()
        XCTAssertEqual(model.list.posts.map(\.id), ["a", "b", "c", "d", "e"])
        XCTAssertFalse(model.wantsMore)

        await model.loadMore()
        XCTAssertEqual(fake.savedPageCursors, [nil, "2", "4"]) // no request after the end
    }

    func testFailedPageKeepsLoadedPostsAndRetriesTheSameCursor() async {
        let fake = FakeFeedService()
        fake.feed = bookmarked(["a", "b", "c"])
        fake.savedPageSize = 2
        let model = SavedPostsModel(panel: makeModel(fake), kind: .bookmarks)
        await model.loadMore()

        fake.failLoad = true
        await model.loadMore()
        XCTAssertEqual(model.list.posts.map(\.id), ["a", "b"])
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(model.wantsMore)
        await model.loadMore() // the error footer is showing; nothing loads until retry

        fake.failLoad = false
        model.retry()
        XCTAssertTrue(model.wantsMore)
        await model.loadMore()
        XCTAssertEqual(model.list.posts.map(\.id), ["a", "b", "c"])
        XCTAssertNil(model.loadError)
        XCTAssertEqual(fake.savedPageCursors, [nil, "2", "2"])
    }

    func testLikesSkipPostsAlreadyShown() async {
        let fake = FakeFeedService()
        // Liked again between pages, "b" comes back on the next page.
        fake.feed = ["a", "b", "b", "c"].map { id in
            var post = TestFactory.feedPost(id: id)
            post.isLiked = true
            return post
        }
        fake.savedPageSize = 2
        let model = SavedPostsModel(panel: makeModel(fake), kind: .likes)

        await model.loadMore()
        await model.loadMore()

        XCTAssertEqual(model.list.posts.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(model.wantsMore)
    }

    func testCanceledLoadLeavesTheListUntouched() async {
        let fake = FakeFeedService()
        fake.feed = bookmarked(["a"])
        let model = SavedPostsModel(panel: makeModel(fake), kind: .bookmarks)

        let load = Task { await model.loadMore() }
        load.cancel() // the view went away
        await load.value

        XCTAssertTrue(model.list.posts.isEmpty)
        XCTAssertNil(model.loadError)
        XCTAssertTrue(model.wantsMore) // the next appearance loads the first page again
    }

    func testEmptyListEndsAfterOneRequest() async {
        let fake = FakeFeedService()
        let model = SavedPostsModel(panel: makeModel(fake), kind: .likes)

        await model.loadMore()
        await model.loadMore()

        XCTAssertTrue(model.list.posts.isEmpty)
        XCTAssertFalse(model.wantsMore)
        XCTAssertEqual(fake.savedPageCursors, [nil])
    }
}
