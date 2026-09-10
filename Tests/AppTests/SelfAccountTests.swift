@testable import CrossPost
import XCTest

@MainActor
final class SelfAccountTests: FeedPanelTestCase {
    func testHandleFallbackRecognizesLocalAndFullHandlesButNotRemoteNamesakes() {
        let store = makeStore()
        store.mastodonUsername = "Me"
        XCTAssertTrue(store.isOwnAccount(.mastodon, handle: " @ME@H.IO "))
        XCTAssertTrue(store.isOwnAccount(.mastodon, handle: "me"))
        XCTAssertFalse(store.isOwnAccount(.mastodon, handle: "@me@elsewhere.social"))
        XCTAssertTrue(store.isOwnAccount(.bluesky, handle: " @ME.BSKY.SOCIAL "))
        XCTAssertFalse(store.isOwnAccount(.bluesky, handle: ""))
        store.mastodonUsername = ""
        XCTAssertFalse(store.isOwnAccount(.mastodon, handle: ""))
    }

    func testVerifiedIdentitySurvivesHandleSpellingAndExpiresWhenCredentialsChange() {
        let store = makeStore()
        for target in PostTarget.allCases {
            store.rememberOwnAccount("own-id", for: target)
            XCTAssertTrue(store.isOwnAccount(target, id: "own-id", handle: "@old-handle"))
            XCTAssertFalse(store.isOwnAccount(target, id: "someone-else", handle: "@me.bsky.social"))
        }
        store.mastodonToken = "other-token"
        store.blueskyAppPassword = "other-password"
        XCTAssertFalse(store.isOwnAccount(.mastodon, id: "own-id"))
        XCTAssertFalse(store.isOwnAccount(.bluesky, id: "own-id"))
    }

    func testSelfNotificationRowsAreHiddenButNewestServerMarkerIsRetained() async {
        let fake = FakeFeedService()
        let store = makeStore()
        store.rememberOwnAccount("me", for: .mastodon)
        let own = FeedNotification.fixture(id: "own", date: Date(), actorID: "me")
        let other = FeedNotification.fixture(id: "other", date: Date(), actorID: "friend")
        let model = FeedPanelModel(target: .mastodon, store: store) { _, _ in fake }
        fake.notificationsToReturn = [own, other]
        model.switchTo(.notifications)
        await waitUntil { !model.isLoading }
        XCTAssertEqual(model.notifications, [other])
        XCTAssertEqual(fake.markedReadCalls, [own])
        XCTAssertTrue(fake.relationshipsRequests.allSatisfy { !$0.contains("me") })

        fake.notificationsToReturn = [own]
        model.refresh()
        await waitUntil { !model.isLoading }
        XCTAssertTrue(model.notifications.isEmpty)
        XCTAssertEqual(fake.markedReadCalls, [own, own])
        model.stop()
    }

    func testOwnPollEndedRemainsVisibleWithoutFollowStateLookup() async {
        let fake = FakeFeedService()
        let store = makeStore()
        store.rememberOwnAccount("me", for: .mastodon)
        let poll = FeedNotification(id: "poll", kind: .poll, actorName: "Me", actorHandle: "@me",
                                    actorID: "me", avatarURL: nil, post: nil, date: Date())
        fake.notificationsToReturn = [poll]
        let model = FeedPanelModel(target: .mastodon, store: store) { _, _ in fake }
        model.switchTo(.notifications)
        await waitUntil { !model.isLoading }
        XCTAssertEqual(model.notifications, [poll])
        XCTAssertTrue(fake.relationshipsRequests.isEmpty)
        model.stop()
    }

    func testBothFollowEntryPointsRejectSelfAfterServiceEstablishesIdentity() async {
        let fake = FakeFeedService()
        let store = makeStore()
        let model = FeedPanelModel(target: .mastodon, store: store) { _, store in
            store.rememberOwnAccount("me", for: .mastodon)
            return fake
        }
        do {
            _ = try await model.remoteFollow(actorID: "me", generation: model.mutationGeneration)
            XCTFail("A notification must not follow the signed-in account")
        } catch {
            XCTAssertTrue(error.userMessage.contains("your own account"))
        }
        do {
            _ = try await model.setFollowing(true, for: "me", current: AccountRelationship())
            XCTFail("A profile must not follow the signed-in account")
        } catch {
            XCTAssertTrue(error.userMessage.contains("your own account"))
        }
        XCTAssertTrue(fake.setFollowingCalls.isEmpty)
        XCTAssertFalse(model.isFollowing("me"))
    }

    func testOwnProfileFromGenericRouteHidesRelationshipControls() {
        let store = makeStore()
        store.rememberOwnAccount("me", for: .bluesky)
        let model = FeedPanelModel(target: .bluesky, store: store) { _, _ in FakeFeedService() }
        let ref = ProfileRef(id: "me", handle: "@old-handle", name: "Me", avatar: nil)
        XCTAssertFalse(ref.isMe)
        let view = ProfileView(panel: model, store: store, ref: ref, push: { _ in })
        XCTAssertTrue(view.isOwnProfile)
    }
}
