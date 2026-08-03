@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelModelTests: FeedPanelTestCase {
    // MARK: Service lifecycle

    // Service-build and call gating uses the shared TestGate (FakeFeedService.swift).

    func testRestartRetriesLiveCallerAgainstFreshService() async {
        let stale = FakeFeedService()
        stale.feed = [TestFactory.feedPost(id: "stale")]
        let fresh = FakeFeedService()
        fresh.feed = [TestFactory.feedPost(id: "fresh")]
        let gate = TestGate()
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
        let staleCaller = Task { try? await model.profile(id: "p") }
        await waitUntil { gate.arrivals == 1 }

        // Credentials change: restart drops the cached service and builds anew.
        model.start()
        await waitUntil { model.posts.map(\.id) == ["fresh"] }

        // The still-live caller retries against the current generation instead of
        // surfacing the shared build's internal cancellation.
        gate.open()
        let recoveredProfile = await staleCaller.value
        XCTAssertEqual(recoveredProfile?.id, "p")
        XCTAssertEqual(stale.profileRequests, [])
        XCTAssertEqual(fresh.profileRequests, ["p"])

        model.refresh()
        await waitUntil { stale.loadFeedCalls + fresh.loadFeedCalls == 2 }
        XCTAssertEqual(model.posts.map(\.id), ["fresh"])
        XCTAssertEqual(stale.loadFeedCalls, 0)
        model.stop()
    }

    func testStopCancelsInFlightServiceBuild() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        let model = FeedPanelModel(target: .bluesky, store: makeStore()) { _, _ in
            await gate.wait()
            return fake
        }

        let caller = Task { try? await model.profile(id: "p") }
        await waitUntil { gate.arrivals == 1 }

        model.stop()
        gate.open()
        let profile = await caller.value
        XCTAssertNil(profile, "a service build finishing after stop() must not be used")
    }

    func testAllWaitersRejectCancellationIgnoringServiceBuild() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        var builds = 0
        var callersStarted = 0
        let model = FeedPanelModel(target: .bluesky, store: makeStore()) { _, _ in
            builds += 1
            await gate.wait()
            return fake
        }

        let first = Task {
            callersStarted += 1
            return try? await model.profile(id: "first")
        }
        let second = Task {
            callersStarted += 1
            return try? await model.profile(id: "second")
        }
        await waitUntil { callersStarted == 2 && gate.arrivals == 1 }

        model.stop()
        gate.open()

        let firstProfile = await first.value
        let secondProfile = await second.value
        XCTAssertNil(firstProfile)
        XCTAssertNil(secondProfile)
        XCTAssertEqual(builds, 1)
    }

    func testCanceledWaiterDoesNotReachProviderAfterSharedBuild() async throws {
        let fake = FakeFeedService()
        let gate = TestGate()
        var callersStarted = 0
        var builds = 0
        let model = FeedPanelModel(target: .bluesky, store: makeStore()) { _, _ in
            builds += 1
            await gate.wait()
            return fake
        }

        let canceled = Task {
            callersStarted += 1
            return try await model.profile(id: "canceled")
        }
        let live = Task {
            callersStarted += 1
            return try await model.profile(id: "live")
        }
        await waitUntil { callersStarted == 2 && gate.arrivals == 1 }

        canceled.cancel()
        gate.open()

        let canceledResult = await canceled.result
        if case let .failure(error) = canceledResult {
            XCTAssertTrue(error is CancellationError)
        } else {
            XCTFail("the canceled waiter must finish with CancellationError")
        }
        let liveProfile = try await live.value
        XCTAssertEqual(liveProfile.id, "live")
        XCTAssertEqual(fake.profileRequests, ["live"])
        XCTAssertEqual(builds, 1)
    }

    func testFailedBuildFromCanceledWaiterDoesNotPoisonNextCaller() async throws {
        let fake = FakeFeedService()
        let gate = TestGate()
        var builds = 0
        let model = FeedPanelModel(target: .bluesky, store: makeStore()) { _, _ in
            builds += 1
            if builds == 1 {
                await gate.wait()
                throw FakeFeedService.FakeError.boom
            }
            return fake
        }
        let canceled = Task { try await model.profile(id: "canceled") }
        await waitUntil { gate.arrivals == 1 }

        canceled.cancel()
        gate.open()
        if case let .failure(error) = await canceled.result {
            XCTAssertTrue(error is CancellationError)
        } else {
            XCTFail("the canceled waiter must not consume the replacement service")
        }

        let profile = try await model.profile(id: "current")
        XCTAssertEqual(profile.id, "current")
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(fake.profileRequests, ["current"])
    }

    func testTabSwitchStopsCanceledWaitersBeforeProviderCalls() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        let model = FeedPanelModel(target: .bluesky, store: makeStore()) { _, _ in
            await gate.wait()
            return fake
        }

        model.start()
        await waitUntil { gate.arrivals == 1 }
        await Task.yield()
        model.switchTo(.notifications)
        gate.open()

        await waitUntil { fake.notificationsCalls == 1 }
        XCTAssertEqual(fake.loadFeedCalls, 0)
        XCTAssertEqual(fake.unreadCountCalls, 0)
        model.stop()
    }

    func testStartWithClearedCredentialsStopsAndFlagsNeedsCredentials() async {
        let fake = FakeFeedService()
        fake.feed = [TestFactory.feedPost(id: "p1")]
        let store = makeStore()
        let model = FeedPanelModel(target: .mastodon, store: store) { _, _ in fake }
        model.start()
        await waitUntil { !model.posts.isEmpty }

        // Credentials cleared (e.g. a future sign-out): restart must tear everything
        // down — no stale loading state — and surface the connect prompt.
        store.mastodonInstanceURL = ""
        store.mastodonToken = ""
        model.start()

        XCTAssertTrue(model.needsCredentials)
        XCTAssertFalse(
            model.isLoading,
            "the cleared-credential restart must not leave a spinner running"
        )
        model.stop()
    }

    func testCredentialRestartInvalidatesOldMutationResults() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let gate = TestGate()
        let post = TestFactory.feedPost(target: .mastodon, id: "same")
        var replacement = post
        replacement.isBookmarked = true
        fake.feed = [replacement]
        model.posts = [post]
        var remoteReturned = false

        model.mutate(post, optimistic: { $0.isLiked = true }, action: { _, _ in
            await gate.wait()
            remoteReturned = true
            throw FakeFeedService.FakeError.boom
        })
        await waitUntil { gate.arrivals == 1 }

        model.start()
        await waitUntil { model.posts == [replacement] }
        XCTAssertTrue(model.inFlight.isEmpty)

        gate.open()
        await waitUntil { remoteReturned }
        XCTAssertEqual(model.posts, [replacement])
        XCTAssertNil(model.actionError)
        model.stop()
    }

    func testFeedSwitchInvalidatesOldMutationResults() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let gate = TestGate()
        let post = TestFactory.feedPost(target: .mastodon, id: "same")
        var replacement = post
        replacement.isBookmarked = true
        fake.feed = [replacement]
        model.posts = [post]
        var remoteReturned = false

        model.mutate(post, optimistic: { $0.isLiked = true }, action: { _, _ in
            await gate.wait()
            remoteReturned = true
            throw FakeFeedService.FakeError.boom
        })
        await waitUntil { gate.arrivals == 1 }

        model.switchTo(.notifications)
        model.switchTo(.home)
        await waitUntil { model.posts == [replacement] }

        gate.open()
        await waitUntil { remoteReturned }
        XCTAssertEqual(model.posts, [replacement])
        XCTAssertNil(model.actionError)
        model.stop()
    }
}
