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
            if Date() >= deadline {
                XCTFail("condition not met within timeout", file: file, line: line)
                return
            }
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

    func testInvalidatedDeleteFailureCannotRestoreRowOrReportError() async {
        let fake = FakeFeedService()
        fake.failDelete = true
        let gate = TestGate()
        fake.deleteDelay = { await gate.wait() }
        let panel = makeModel(fake)
        let list = PostList(panel: panel)
        let posts = ["a", "b"].map {
            TestFactory.feedPost(target: .bluesky, id: $0)
        }
        list.posts = posts

        list.delete(posts[0])
        await waitUntil { gate.arrivals == 1 }
        list.invalidateOptimisticMutations()
        gate.open()
        await waitUntil { fake.deleteCompletions == 1 }
        await Task.yield()

        XCTAssertEqual(list.posts.map(\.id), ["b"])
        XCTAssertTrue(list.inFlight.isEmpty)
        XCTAssertNil(panel.actionError)
    }

    /// Delete-vs-poll race: while a delete is in flight its id sits in `inFlight`
    /// with no local row, and the timeline merge drops that id from the fetched
    /// page — the row the user just removed must not be resurrected.
    func testPollMergeDuringDeleteDoesNotResurrectRow() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        fake.deleteDelay = { await gate.wait() }
        let list = PostList(panel: makeModel(fake))
        let posts = ["a", "b"].map { TestFactory.feedPost(target: .bluesky, id: $0) }
        list.posts = posts

        list.delete(posts[0])
        XCTAssertEqual(list.posts.map(\.id), ["b"])
        XCTAssertTrue(list.inFlight.contains("a"), "a deleting id must be registered in-flight")

        // A 30s poll returns a page fetched before the server applied the delete.
        await waitUntil { gate.arrivals == 1 }
        list.posts = FeedMerge.merge(existing: list.posts, fetched: posts,
                                     preservingIDs: list.inFlight,
                                     excludingIDs: list.inFlight.subtracting(list.posts.map(\.id)))
        XCTAssertEqual(list.posts.map(\.id), ["b"], "the merge must not re-add the deleting row")

        gate.open()
        await waitUntil { list.inFlight.isEmpty }
        XCTAssertEqual(list.posts.map(\.id), ["b"])   // still gone after the delete lands
    }

    /// A failed delete re-inserts next to its old neighbor even when a concurrent
    /// merge shifted every index while the delete was in flight.
    func testDeleteFailureReInsertsNextToOldNeighborAfterConcurrentMerge() async {
        let fake = FakeFeedService()
        fake.failDelete = true
        let gate = TestGate()
        fake.deleteDelay = { await gate.wait() }
        let list = PostList(panel: makeModel(fake))
        list.posts = ["a", "b", "c"].map { TestFactory.feedPost(target: .bluesky, id: $0) }

        list.delete(list.posts[1])                            // remove "b" (index 1)
        XCTAssertEqual(list.posts.map(\.id), ["a", "c"])

        // A merge lands a new post on top while the delete is in flight, shifting
        // every index down by one.
        await waitUntil { gate.arrivals == 1 }
        list.posts = [TestFactory.feedPost(target: .bluesky, id: "new")] + list.posts

        gate.open()                                           // the delete now fails
        await waitUntil { list.posts.count == 4 }
        XCTAssertEqual(list.posts.map(\.id), ["new", "a", "b", "c"],
                       "the restore must anchor on the old neighbor, not the stale index")
    }

    /// A second delete of the same post while one is in flight is ignored — the
    /// remote delete runs exactly once.
    func testConcurrentDeleteIsDedupedWhileInFlight() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        fake.deleteDelay = { await gate.wait() }
        let list = PostList(panel: makeModel(fake))
        let post = TestFactory.feedPost(target: .bluesky, id: "a")
        list.posts = [post]

        list.delete(post)
        await waitUntil { gate.arrivals == 1 }
        list.delete(post)                                     // same id already in flight
        gate.open()
        await waitUntil { list.inFlight.isEmpty }

        XCTAssertEqual(fake.deletedIDs, ["a"], "the remote delete must run exactly once")
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

    /// A second toggle while the first is in flight hits the `!inFlight.contains`
    /// guard and is dropped — the row ends single-toggled and the remote runs once,
    /// never double-applied back to the original.
    func testConcurrentLikeIsDedupedWhileInFlight() async {
        let fake = FakeFeedService()
        let list = PostList(panel: makeModel(fake))
        var post = TestFactory.feedPost(target: .bluesky)
        post.likeCount = 5
        list.posts = [post]

        list.toggleLike(post)   // inserts id into inFlight synchronously, before its Task runs
        list.toggleLike(post)   // same id already in flight → ignored, not toggled back
        XCTAssertTrue(list.posts[0].isLiked)            // single toggle stuck
        XCTAssertEqual(list.posts[0].likeCount, 6)      // not re-decremented by the second call

        await waitUntil { list.posts[0].likeRecordURI != nil }   // reconciled
        XCTAssertEqual(fake.likeSetCalls, [true])       // remote invoked exactly once
        XCTAssertTrue(list.posts[0].isLiked)
        XCTAssertEqual(list.posts[0].likeCount, 6)
    }

    /// A toggle on a post id not in `posts` hits the guard's second clause: no row,
    /// so nothing is marked in-flight and no remote call is ever made.
    func testToggleOnAbsentPostIsNoOp() async {
        let fake = FakeFeedService()
        let list = PostList(panel: makeModel(fake))
        let present = TestFactory.feedPost(target: .bluesky, id: "present")
        list.posts = [present]

        list.toggleLike(TestFactory.feedPost(target: .bluesky, id: "absent"))
        XCTAssertTrue(list.inFlight.isEmpty)            // guard returned before inserting
        XCTAssertEqual(list.posts.map(\.id), ["present"])
        XCTAssertFalse(list.posts[0].isLiked)

        await waitUntil { list.inFlight.isEmpty }       // no Task spawned to flip it
        XCTAssertEqual(fake.likeSetCalls, [])           // remote never called
    }
    func testOldSuccessCannotReconcileOrClearNewGenerationMutation() async {
        let list = PostList(panel: makeModel(FakeFeedService()))
        let post = TestFactory.feedPost(target: .bluesky, id: "same")
        let oldGate = TestGate()
        let newGate = TestGate()
        var oldRemoteReturned = false
        list.posts = [post]

        list.mutate(post, optimistic: { $0.isLiked = true }) { optimistic in
            await oldGate.wait()
            oldRemoteReturned = true
            var updated = optimistic
            updated.isPinned = true
            return updated
        }
        await waitUntil { oldGate.arrivals == 1 }

        list.invalidateOptimisticMutations()
        list.mutate(list.posts[0], optimistic: { _ in }) { optimistic in
            await newGate.wait()
            var updated = optimistic
            updated.isBookmarked = true
            return updated
        }
        await waitUntil { newGate.arrivals == 1 }

        oldGate.open()
        await waitUntil { oldRemoteReturned }

        XCTAssertTrue(list.inFlight.contains(post.id))
        XCTAssertFalse(list.posts[0].isPinned)

        newGate.open()
        await waitUntil { list.inFlight.isEmpty }
        XCTAssertTrue(list.posts[0].isLiked)
        XCTAssertTrue(list.posts[0].isBookmarked)
        XCTAssertFalse(list.posts[0].isPinned)
    }

    func testOldFailureCannotClearOrRevertNewGenerationMutation() async {
        let panel = makeModel(FakeFeedService())
        let list = PostList(panel: panel)
        let post = TestFactory.feedPost(target: .bluesky, id: "same")
        let oldGate = TestGate()
        let newGate = TestGate()
        var oldRemoteReturned = false
        list.posts = [post]

        list.mutate(post, optimistic: { $0.isLiked = true }) { _ in
            await oldGate.wait()
            oldRemoteReturned = true
            throw FakeFeedService.FakeError.boom
        }
        await waitUntil { oldGate.arrivals == 1 }

        list.invalidateOptimisticMutations()
        list.posts = [post]
        list.mutate(post, optimistic: { $0.isBookmarked = true }) { optimistic in
            await newGate.wait()
            var updated = optimistic
            updated.isPinned = true
            return updated
        }
        await waitUntil { newGate.arrivals == 1 }

        oldGate.open()
        await waitUntil { oldRemoteReturned }

        XCTAssertTrue(list.inFlight.contains(post.id))
        XCTAssertTrue(list.posts[0].isBookmarked)
        XCTAssertNil(panel.actionError)

        newGate.open()
        await waitUntil { list.inFlight.isEmpty }
        XCTAssertTrue(list.posts[0].isBookmarked)
        XCTAssertTrue(list.posts[0].isPinned)
    }
}
