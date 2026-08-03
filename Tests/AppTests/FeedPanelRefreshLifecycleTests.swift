@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelRefreshLifecycleTests: FeedPanelTestCase {
    func testFailedReadMarkLeavesBadgeUncleared() async {
        let fake = FakeFeedService()
        fake.failMarkRead = true
        fake.notificationsToReturn = [.fixture(id: "n1", date: Date(timeIntervalSince1970: 1))]
        let model = makeModel(fake)
        model.unreadCount = 3

        model.switchTo(.notifications)
        await waitUntil { !model.notifications.isEmpty }

        XCTAssertEqual(model.unreadCount, 3, "a failed read-mark must not falsely clear the badge")
        XCTAssertNotNil(model.actionError, "a failed read-mark must surface a retryable error")
        model.stop()
    }

    /// A notifications load superseded by a tab switch must not zero the badge or
    /// cancel the successor's unread fetch once its read-mark finally returns.
    func testSupersededNotificationsLoadDoesNotClearBadgeAfterTabSwitch() async {
        let fake = FakeFeedService()
        fake.notificationsToReturn = [.fixture(id: "n1", date: Date(timeIntervalSince1970: 1))]
        fake.unread = 4
        let gate = TestGate()
        fake.markReadDelay = { await gate.wait() }
        let model = makeModel(fake)

        model.switchTo(.notifications)
        await waitUntil { gate.arrivals == 1 } // load is suspended inside the read-mark

        model.switchTo(.home) // supersedes the load, refetches the badge
        await waitUntil { model.unreadCount == 4 }

        gate.open() // the stale load's read-mark returns now
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(
            model.unreadCount,
            4,
            "a superseded notifications load must not zero the badge"
        )
        model.stop()
    }

    func testStopClearsTransientActionError() {
        let model = makeModel(FakeFeedService())
        model.reportError("boom")

        model.stop()

        XCTAssertNil(model.actionError)
    }

    /// The banner dismiss timer is keyed to the banner instance, not its text: a
    /// renewed identical banner gets a fresh timeout instead of dying on the old timer.
    func testRenewedIdenticalBannerGetsAFreshDismissTimer() async {
        let model = makeModel(FakeFeedService())
        model.actionErrorDismissDelay = 400_000_000

        model.reportError("boom")
        try? await Task.sleep(nanoseconds: 200_000_000)
        model.reportError("boom") // renew with the identical message
        try? await Task.sleep(nanoseconds: 300_000_000) // the first timer has fired by now
        XCTAssertEqual(
            model.actionError,
            "boom",
            "the old timer must not dismiss the renewed banner"
        )

        await waitUntil { model.actionError == nil } // the renewed timer still dismisses it
    }

    /// The live-update loop re-acquires self weakly per iteration, so a model
    /// discarded without stop() deallocates instead of being pinned by the open stream.
    func testOpenLiveStreamDoesNotKeepDiscardedModelAlive() async {
        let fake = FakeFeedService()
        var continuation: AsyncStream<Void>.Continuation?
        fake.liveStream = AsyncStream { continuation = $0 } // stays open until test end
        var model: FeedPanelModel? = makeModel(fake) // .mastodon → live stream runs
        model?.start()
        await waitUntil { fake.liveUpdatesCalls == 1 } // the loop is inside the stream

        weak var weakModel: FeedPanelModel?
        weakModel = model
        model = nil // discarded without stop()
        await waitUntil { weakModel == nil }
        continuation?.finish()
    }

    func testReplacingLiveTaskClearsConnectionBeforeReplacementConnects() async {
        let fake = FakeFeedService()
        var continuation: AsyncStream<Void>.Continuation?
        fake.liveStream = AsyncStream { continuation = $0 }
        let model = makeModel(fake)
        model.start()
        await waitUntil { model.isLiveConnected }

        model.startLiveUpdates()

        XCTAssertFalse(model.isLiveConnected)
        model.stop()
        continuation?.finish()
    }

    func testStaleLiveCleanupCannotDisconnectReplacementOrResumeFeedPolling() async {
        let stale = FakeFeedService()
        let replacement = FakeFeedService()
        let staleStreamGate = FeedPanelGate()
        let pollGate = FeedPanelGate()
        var replacementContinuation: AsyncStream<Void>.Continuation?
        stale.liveStream = AsyncStream(unfolding: {
            await staleStreamGate.wait()
            return nil
        })
        replacement.liveStream = AsyncStream { replacementContinuation = $0 }
        var builds = 0
        let model = FeedPanelModel(target: .mastodon, store: makeStore()) { _, _ in
            builds += 1
            return builds == 1 ? stale : replacement
        }
        model.applicationIsActive = { true }
        model.pollSleep = { _ in await pollGate.wait() }
        let staleTaskExited = expectation(description: "stale live task exited")
        model.liveTaskDidExit = { staleTaskExited.fulfill() }

        model.start()
        await waitUntil {
            model.isLiveConnected
                && staleStreamGate.arrivals == 1
                && pollGate.arrivals == 1
        }

        model.start()
        await waitUntil {
            model.isLiveConnected
                && replacement.liveUpdatesCalls == 1
                && replacement.loadFeedCalls == 1
                && pollGate.arrivals == 2
        }
        let connectedLoadCount = replacement.loadFeedCalls

        staleStreamGate.open()
        await fulfillment(of: [staleTaskExited], timeout: 2)
        XCTAssertTrue(model.isLiveConnected)
        model.liveTaskDidExit = {}
        pollGate.open()
        await waitUntil { pollGate.departures == 2 && pollGate.arrivals == 3 }
        await Task.yield()

        XCTAssertTrue(model.isLiveConnected)
        XCTAssertEqual(
            replacement.loadFeedCalls,
            connectedLoadCount,
            "stale teardown must not re-enable the polling fallback for a connected stream"
        )
        model.stop()
        pollGate.open()
        replacementContinuation?.finish()
    }

    func testLiveBurstRunsOneActiveAndOnePendingFeedLoad() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        var continuation: AsyncStream<Void>.Continuation?
        fake.liveStream = AsyncStream { continuation = $0 }
        fake.loadDelay = { await gate.wait() }
        let model = makeModel(fake)
        model.start()
        await waitUntil { gate.arrivals == 1 && fake.liveUpdatesCalls == 1 }

        continuation?.yield()
        continuation?.yield()
        continuation?.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.loadFeedCalls, 1, "stream bursts must not start parallel feed loads")

        fake.loadDelay = nil
        gate.open()
        await waitUntil { fake.loadFeedCalls == 2 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.loadFeedCalls, 2, "a burst needs at most one trailing refresh")
        model.stop()
        continuation?.finish()
    }

    func testUnchangedFeedRefreshDoesNotPublishPostsAgain() async {
        let fake = FakeFeedService()
        fake.feed = [TestFactory.feedPost(id: "same")]
        let model = makeModel(fake)
        model.start()
        await waitUntil { model.posts == fake.feed }

        let publication = expectation(description: "posts publication")
        publication.isInverted = true
        withObservationTracking {
            _ = model.posts
        } onChange: {
            publication.fulfill()
        }

        model.refresh()
        await waitUntil { fake.loadFeedCalls == 2 }
        await fulfillment(of: [publication], timeout: 0.1)
        model.stop()
    }

    func testCredentialRestartClearsSnapshotsAndRejectsOldRowMutation() async {
        let fake = FakeFeedService()
        let store = makeStore()
        let model = FeedPanelModel(target: .bluesky, store: store) { _, _ in fake }
        let post = TestFactory.feedPost(id: "old-post")
        let notification = FeedNotification.fixture(
            id: "old-notification",
            date: Date(),
            actorID: "old-actor"
        )
        model.posts = [post]
        model.notifications = [notification]
        model.conversations = [
            Conversation(
                id: "old-conversation",
                otherName: "Old Account",
                otherHandle: "@old",
                otherID: "old",
                otherAvatarURL: nil,
                lastMessage: "old",
                lastDate: nil,
                unreadCount: 1
            )
        ]
        model.reconcileFollow(AccountRelationship(isFollowing: true), for: "old-actor")
        let generation = model.mutationGeneration
        store.blueskyHandle = ""
        store.blueskyAppPassword = ""

        model.restartAfterCredentialsChange()

        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertTrue(model.notifications.isEmpty)
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertFalse(model.isFollowing("old-actor"))
        XCTAssertEqual(model.unreadCount, 0)
        XCTAssertTrue(model.needsCredentials)

        do {
            _ = try await model.remoteSetLiked(true, on: post, generation: generation)
            XCTFail("an old notification row must not mutate through replacement credentials")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(fake.likeSetCalls.isEmpty)
    }
}
