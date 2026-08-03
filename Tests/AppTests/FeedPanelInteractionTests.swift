import AppKit
@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelInteractionTests: FeedPanelTestCase {
    // MARK: Notifications loading

    func testLoadingNotificationsStoresFetchedMarksNewestAndClearsBadge() async {
        let fake = FakeFeedService()
        let newest = FeedNotification.fixture(id: "n2", date: Date(timeIntervalSince1970: 200))
        let older = FeedNotification.fixture(id: "n1", date: Date(timeIntervalSince1970: 100))
        fake.notificationsToReturn = [newest, older] // services return newest-first
        let model = makeModel(fake)
        model.unreadCount = 5

        model.switchTo(.notifications)
        await waitUntil { !model.notifications.isEmpty }

        XCTAssertEqual(model.notifications.map(\.id), ["n2", "n1"])
        XCTAssertEqual(model.unreadCount, 0) // badge cleared
        XCTAssertEqual(fake.markedReadCalls, [newest]) // marked read up to the newest only
        model.stop()
    }

    func testLoadingNotificationsResolvesFollowStateInOneBatch() async {
        let fake = FakeFeedService()
        fake.notificationsToReturn = [
            .fixture(id: "n1", date: Date(timeIntervalSince1970: 200), actorID: "friend"),
            .fixture(id: "n2", date: Date(timeIntervalSince1970: 100), actorID: "stranger")
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

    func testRemoteFollowSkipsWriteForAlreadyFollowedActor() async throws {
        let fake = FakeFeedService()
        fake.relationshipsToReturn = ["friend": AccountRelationship(isFollowing: true)]
        let model = makeModel(fake)

        let updated = try await model.remoteFollow(
            actorID: "friend",
            generation: model.mutationGeneration
        )
        model.reconcileFollow(updated, for: "friend")

        XCTAssertTrue(model.isFollowing("friend"), "state reflects the resolved relationship")
        XCTAssertEqual(fake.setFollowingCalls, [], "already following — no follow/unfollow request")
    }

    func testRemoteFollowWritesAndReconcilesSharedState() async throws {
        let fake = FakeFeedService()
        let model = makeModel(fake)

        let updated = try await model.remoteFollow(
            actorID: "stranger",
            generation: model.mutationGeneration
        )
        model.reconcileFollow(updated, for: "stranger")

        XCTAssertTrue(model.isFollowing("stranger"))
        XCTAssertEqual(fake.setFollowingCalls, ["stranger:true"])
    }

    func testNotificationFollowStateMergesInsteadOfReplacing() async throws {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        // The user follows someone who isn't in any notification page.
        let updated = try await model.remoteFollow(
            actorID: "friend",
            generation: model.mutationGeneration
        )
        model.reconcileFollow(updated, for: "friend")
        XCTAssertTrue(model.isFollowing("friend"))

        // Loading a notifications page that resolves a different actor must not
        // wipe the follow we just made — the batch merges into the set.
        fake.notificationsToReturn = [
            .fixture(
                id: "n1",
                date: Date(timeIntervalSince1970: 1),
                actorID: "other"
            )
        ]
        fake.relationshipsToReturn = ["other": AccountRelationship(isFollowing: true)]
        model.switchTo(.notifications)
        await waitUntil { model.isFollowing("other") }

        XCTAssertTrue(model.isFollowing("friend"), "a follow outside the page must survive a load")
        model.stop()
    }

    // MARK: isMine (controls delete/pin)

    func testIsMineMatchesOwnBlueskyHandleCaseInsensitively() {
        let model = makeModel(FakeFeedService(), target: .bluesky)
        let mine = TestFactory.feedPost(
            target: .bluesky,
            authorHandle: "@me.bsky.social"
        )
        let mineUppercased = TestFactory.feedPost(
            target: .bluesky,
            authorHandle: "@ME.BSKY.SOCIAL"
        )
        let other = TestFactory.feedPost(
            target: .bluesky,
            authorHandle: "@other.bsky.social"
        )
        XCTAssertTrue(model.isMine(mine))
        XCTAssertTrue(model.isMine(mineUppercased))
        XCTAssertFalse(model.isMine(other))
    }

    func testIsMineMatchesOwnMastodonUsername() {
        let store = AccountStore()
        store.mastodonUsername = "me@h.io"
        let model = FeedPanelModel(
            target: .mastodon,
            store: store
        ) { _, _ in FakeFeedService() }
        let mine = TestFactory.feedPost(
            target: .mastodon,
            authorHandle: "@me@h.io"
        )
        let other = TestFactory.feedPost(
            target: .mastodon,
            authorHandle: "@someone@h.io"
        )
        XCTAssertTrue(model.isMine(mine))
        XCTAssertFalse(model.isMine(other))
    }

    // MARK: Error routing (empty sticky vs transient vs silent)

    func testFailedLoadOnEmptyFeedSetsStickyEmptyStateError() async {
        let fake = FakeFeedService()
        fake.failLoad = true
        let model = makeModel(fake)
        model.refresh()
        await waitUntil { model.errorMessage != nil }
        XCTAssertNil(
            model.actionError,
            "an empty-feed failure uses the sticky empty state, not the banner"
        )
        XCTAssertTrue(model.posts.isEmpty)
        model.stop()
    }

    func testFailedRefreshWithContentShowsTransientBannerNotStickyError() async {
        let fake = FakeFeedService()
        fake.feed = [TestFactory.feedPost(target: .mastodon, id: "p1")]
        let model = makeModel(fake)
        model.refresh()
        await waitUntil { !model.posts.isEmpty } // first load succeeds

        fake.failLoad = true
        model.refresh() // user refresh fails with content present
        await waitUntil { model.actionError != nil }
        XCTAssertNil(
            model.errorMessage,
            "a refresh failure with content must not set the sticky banner"
        )
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
        XCTAssertTrue(model.posts[0].isLiked) // optimistic, synchronous
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
        XCTAssertTrue(model.posts[0].isLiked) // optimistic

        await waitUntil { model.actionError != nil }
        XCTAssertFalse(model.posts[0].isLiked) // rolled back
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

        model.delete(posts[1])
        XCTAssertEqual(model.posts.map(\.id), ["a", "c"]) // optimistic removal

        await waitUntil { model.actionError != nil }
        XCTAssertEqual(model.posts.map(\.id), ["a", "b", "c"]) // restored at original index
    }

    func testDeleteSuccessRemovesRow() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let posts = ["a", "b"].map { TestFactory.feedPost(id: $0) }
        model.posts = posts

        model.delete(posts[0])
        XCTAssertEqual(model.posts.map(\.id), ["b"])

        await waitUntil { fake.deletedIDs.contains("a") }
        XCTAssertEqual(model.posts.map(\.id), ["b"]) // stays removed
    }
}
