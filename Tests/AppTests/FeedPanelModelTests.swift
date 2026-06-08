import XCTest
@testable import CrossPost

@MainActor
final class FeedPanelModelTests: XCTestCase {
    override func tearDown() {
        // @AppStorage lives in a shared test suite; don't leak creds across tests.
        let store = AccountStore()
        store.mastodonInstanceURL = ""
        store.blueskyHandle = ""
        super.tearDown()
    }

    private func makeModel(_ fake: FakeFeedService, target: PostTarget = .mastodon) -> FeedPanelModel {
        let store = AccountStore()
        store.mastodonInstanceURL = "https://h.io"
        store.mastodonToken = "tok"
        store.blueskyHandle = "me.bsky.social"
        store.blueskyAppPassword = "pw"
        return FeedPanelModel(target: target, store: store) { _, _ in fake }
    }

    /// Polls observable model state until `predicate` holds, since the model's
    /// optimistic actions reconcile in a detached Task.
    private func waitUntil(_ predicate: @MainActor () -> Bool, timeout: TimeInterval = 2,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() >= deadline { XCTFail("condition not met within timeout", file: file, line: line); return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    // MARK: Notifications loading

    func testLoadingNotificationsStoresFetchedMarksNewestAndClearsBadge() async {
        let fake = FakeFeedService()
        let newest = FeedNotification.fixture(id: "n2", date: Date(timeIntervalSince1970: 200))
        let older = FeedNotification.fixture(id: "n1", date: Date(timeIntervalSince1970: 100))
        fake.notificationsToReturn = [newest, older]   // services return newest-first
        let model = makeModel(fake)
        model.unreadCount = 5

        model.switchTo(.notifications)
        await waitUntil { !model.notifications.isEmpty }

        XCTAssertEqual(model.notifications.map(\.id), ["n2", "n1"])
        XCTAssertEqual(model.unreadCount, 0)                    // badge cleared
        XCTAssertEqual(fake.markedReadCalls, [newest])          // marked read up to the newest only
        model.stop()
    }

    // MARK: Optimistic like / repost

    func testLikeSuccessUpdatesFlagCountAndRecordURI() async {
        let fake = FakeFeedService()
        let model = makeModel(fake, target: .bluesky)
        let post = TestFactory.feedPost(target: .bluesky)
        model.posts = [post]

        model.toggleLike(post)
        XCTAssertTrue(model.posts[0].isLiked)                   // optimistic, synchronous
        XCTAssertEqual(model.posts[0].likeCount, post.likeCount + 1)

        await waitUntil { model.posts[0].likeRecordURI != nil }
        XCTAssertEqual(model.posts[0].likeRecordURI, "at://like/\(post.id)")
    }

    func testLikeFailureRollsBackAndSurfacesError() async {
        let fake = FakeFeedService()
        fake.failLike = true
        let model = makeModel(fake, target: .bluesky)
        let post = TestFactory.feedPost(target: .bluesky)
        model.posts = [post]

        model.toggleLike(post)
        XCTAssertTrue(model.posts[0].isLiked)                   // optimistic

        await waitUntil { model.actionError != nil }
        XCTAssertFalse(model.posts[0].isLiked)                  // rolled back
        XCTAssertEqual(model.posts[0].likeCount, post.likeCount)
    }

    func testRepostSuccessSetsRecordURI() async {
        let fake = FakeFeedService()
        let model = makeModel(fake, target: .bluesky)
        let post = TestFactory.feedPost(target: .bluesky)
        model.posts = [post]

        model.toggleRepost(post)
        XCTAssertTrue(model.posts[0].isReposted)
        XCTAssertEqual(model.posts[0].repostCount, post.repostCount + 1)

        await waitUntil { model.posts[0].repostRecordURI != nil }
        XCTAssertEqual(model.posts[0].repostRecordURI, "at://repost/\(post.id)")
    }

    // MARK: Delete rollback

    func testDeleteFailureRestoresRowAtOriginalIndex() async {
        let fake = FakeFeedService()
        fake.failDelete = true
        let model = makeModel(fake)
        let posts = ["a", "b", "c"].map { TestFactory.feedPost(id: $0) }
        model.posts = posts

        model.deletePost(posts[1])
        XCTAssertEqual(model.posts.map(\.id), ["a", "c"])       // optimistic removal

        await waitUntil { model.actionError != nil }
        XCTAssertEqual(model.posts.map(\.id), ["a", "b", "c"])  // restored at original index
    }

    func testDeleteSuccessRemovesRow() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let posts = ["a", "b"].map { TestFactory.feedPost(id: $0) }
        model.posts = posts

        model.deletePost(posts[0])
        XCTAssertEqual(model.posts.map(\.id), ["b"])

        await waitUntil { fake.deletedIDs.contains("a") }
        XCTAssertEqual(model.posts.map(\.id), ["b"])            // stays removed
    }
}
