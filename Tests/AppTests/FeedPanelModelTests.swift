import XCTest
@testable import CrossPost

@MainActor
final class FeedPanelModelTests: XCTestCase {
    override func tearDown() {
        // @AppStorage lives in a shared test suite; don't leak creds across tests.
        let store = AccountStore()
        store.mastodonInstanceURL = ""
        store.mastodonUsername = ""
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

    // MARK: Service lifecycle

    /// Suspends service builds until the test releases them, so cancellation
    /// races can be staged deterministically.
    @MainActor
    private final class ServiceGate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var arrivals = 0
        func wait() async {
            arrivals += 1
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    private func makeStore() -> AccountStore {
        let store = AccountStore()
        store.mastodonInstanceURL = "https://h.io"
        store.mastodonToken = "tok"
        store.blueskyHandle = "me.bsky.social"
        store.blueskyAppPassword = "pw"
        return store
    }

    func testRestartDiscardsServiceBuiltBeforeRestart() async {
        let stale = FakeFeedService()
        stale.feed = [TestFactory.feedPost(id: "stale")]
        let fresh = FakeFeedService()
        fresh.feed = [TestFactory.feedPost(id: "fresh")]
        let gate = ServiceGate()
        var builds = 0
        let model = FeedPanelModel(target: .bluesky, store: makeStore()) { _, _ in
            builds += 1
            if builds == 1 {
                await gate.wait()
                return stale
            }
            return fresh
        }

        // A service build starts, then hangs mid-flight (slow network).
        let staleCaller = Task { await model.profile(id: "p") }
        await waitUntil { gate.arrivals == 1 }

        // Credentials change: restart drops the cached service and builds anew.
        model.start()
        await waitUntil { model.posts.map(\.id) == ["fresh"] }

        // The pre-restart build finally completes; it must not be installed.
        gate.open()
        _ = await staleCaller.value

        model.refresh()
        await waitUntil { stale.loadFeedCalls + fresh.loadFeedCalls == 2 }
        XCTAssertEqual(model.posts.map(\.id), ["fresh"])
        XCTAssertEqual(stale.loadFeedCalls, 0)
        model.stop()
    }

    func testStopCancelsInFlightServiceBuild() async {
        let fake = FakeFeedService()
        let gate = ServiceGate()
        let model = FeedPanelModel(target: .bluesky, store: makeStore()) { _, _ in
            await gate.wait()
            return fake
        }

        let caller = Task { await model.profile(id: "p") }
        await waitUntil { gate.arrivals == 1 }

        model.stop()
        gate.open()
        let profile = await caller.value
        XCTAssertNil(profile, "a service build finishing after stop() must not be used")
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

    func testLoadingNotificationsResolvesFollowStateInOneBatch() async {
        let fake = FakeFeedService()
        fake.notificationsToReturn = [
            .fixture(id: "n1", date: Date(timeIntervalSince1970: 200), actorID: "friend"),
            .fixture(id: "n2", date: Date(timeIntervalSince1970: 100), actorID: "stranger"),
        ]
        fake.relationshipsToReturn = ["friend": AccountRelationship(isFollowing: true)]
        let model = makeModel(fake)

        model.switchTo(.notifications)
        await waitUntil { model.isFollowing("friend") }

        XCTAssertFalse(model.isFollowing("stranger"))
        XCTAssertEqual(fake.relationshipsRequests.count, 1, "one batch lookup, not per-row calls")
        XCTAssertEqual(Set(fake.relationshipsRequests[0]), ["friend", "stranger"])
        model.stop()
    }

    func testFollowingAnAlreadyFollowedActorNeverWritesAFollow() async {
        let fake = FakeFeedService()
        fake.relationshipsToReturn = ["friend": AccountRelationship(isFollowing: true)]
        let model = makeModel(fake)

        await model.follow(actorID: "friend")

        XCTAssertTrue(model.isFollowing("friend"), "state reflects the resolved relationship")
        XCTAssertEqual(fake.setFollowingCalls, [], "already following — no follow/unfollow request")
    }

    func testFollowingANewActorFollowsAndUpdatesSharedState() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)

        await model.follow(actorID: "stranger")

        XCTAssertTrue(model.isFollowing("stranger"))
        XCTAssertEqual(fake.setFollowingCalls, ["stranger:true"])
    }

    func testNotificationFollowStateMergesInsteadOfReplacing() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        // The user follows someone who isn't in any notification page.
        await model.follow(actorID: "friend")
        XCTAssertTrue(model.isFollowing("friend"))

        // Loading a notifications page that resolves a different actor must not wipe
        // the follow we just made — the batch merges into the set rather than replacing it.
        fake.notificationsToReturn = [.fixture(id: "n1", date: Date(timeIntervalSince1970: 1), actorID: "other")]
        fake.relationshipsToReturn = ["other": AccountRelationship(isFollowing: true)]
        model.switchTo(.notifications)
        await waitUntil { model.isFollowing("other") }

        XCTAssertTrue(model.isFollowing("friend"), "a follow outside the page must survive a load")
        model.stop()
    }

    // MARK: isMine (controls delete/pin)

    func testIsMineMatchesOwnBlueskyHandleCaseInsensitively() {
        let model = makeModel(FakeFeedService(), target: .bluesky)   // blueskyHandle = "me.bsky.social"
        XCTAssertTrue(model.isMine(TestFactory.feedPost(target: .bluesky, authorHandle: "@me.bsky.social")))
        XCTAssertTrue(model.isMine(TestFactory.feedPost(target: .bluesky, authorHandle: "@ME.BSKY.SOCIAL")))
        XCTAssertFalse(model.isMine(TestFactory.feedPost(target: .bluesky, authorHandle: "@other.bsky.social")))
    }

    func testIsMineMatchesOwnMastodonUsername() {
        let store = AccountStore()
        store.mastodonUsername = "me@h.io"
        let model = FeedPanelModel(target: .mastodon, store: store) { _, _ in FakeFeedService() }
        XCTAssertTrue(model.isMine(TestFactory.feedPost(target: .mastodon, authorHandle: "@me@h.io")))
        XCTAssertFalse(model.isMine(TestFactory.feedPost(target: .mastodon, authorHandle: "@someone@h.io")))
    }

    // MARK: Error routing (empty sticky vs transient vs silent)

    func testFailedLoadOnEmptyFeedSetsStickyEmptyStateError() async {
        let fake = FakeFeedService()
        fake.failLoad = true
        let model = makeModel(fake)
        model.refresh()
        await waitUntil { model.errorMessage != nil }
        XCTAssertNil(model.actionError, "an empty-feed failure uses the sticky empty state, not the banner")
        XCTAssertTrue(model.posts.isEmpty)
        model.stop()
    }

    func testFailedRefreshWithContentShowsTransientBannerNotStickyError() async {
        let fake = FakeFeedService()
        fake.feed = [TestFactory.feedPost(target: .mastodon, id: "p1")]
        let model = makeModel(fake)
        model.refresh()
        await waitUntil { !model.posts.isEmpty }   // first load succeeds

        fake.failLoad = true
        model.refresh()                            // user refresh fails with content present
        await waitUntil { model.actionError != nil }
        XCTAssertNil(model.errorMessage, "a refresh failure with content must not set the sticky banner")
        XCTAssertEqual(model.posts.map(\.id), ["p1"], "stale content stands")
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
