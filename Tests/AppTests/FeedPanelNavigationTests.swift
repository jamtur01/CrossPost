import AppKit
@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelNavigationTests: FeedPanelTestCase {
    // MARK: Search

    func testSearchForwardsQueryAndReturnsResults() async throws {
        let fake = FakeFeedService()
        fake.searchResultsToReturn = SearchResults(posts: [TestFactory.feedPost(id: "r1")])
        let model = makeModel(fake)

        let results = try await model.search("swift")

        XCTAssertEqual(fake.searchQueries, ["swift"])
        XCTAssertEqual(results.posts.map(\.id), ["r1"])
    }

    func testSearchPropagatesError() async {
        let fake = FakeFeedService()
        fake.failLoad = true
        let model = makeModel(fake)
        do {
            _ = try await model.search("x")
            XCTFail("search should propagate the service error")
        } catch { /* expected */ }
    }

    func testFeedSwitchPreventsDelayedProfileNavigation() async throws {
        let fake = FakeFeedService()
        let gate = TestGate()
        let model = makeModel(fake)
        let url = try XCTUnwrap(URL(string: "https://h.io/@alice"))
        fake.profileForURLDelay = { await gate.wait() }
        fake.profileForURLResult = Profile(
            id: "alice", name: "Alice", handle: "@alice@h.io",
            avatarURL: nil, bannerURL: nil, bio: AttributedString(""),
            followers: 0, following: 0, posts: 0, webURL: url
        )
        var pushedRoutes: [String] = []

        model.openLink(url) { pushedRoutes.append($0.id) }
        await waitUntil { gate.arrivals == 1 }

        model.switchTo(.notifications)
        gate.open()
        await waitUntil { fake.profileForURLCompletions == 1 }
        await Task.yield()

        XCTAssertTrue(pushedRoutes.isEmpty)
    }

    func testCopyLinkWritesWebURLToPasteboard() {
        let model = makeModel(FakeFeedService())
        let post = TestFactory.feedPost(id: "https-test")
        // TestFactory posts have no webURL, so build one that does.
        let withURL = FeedPost(
            id: post.id, target: .mastodon, authorName: "A", authorHandle: "@a", avatarURL: nil,
            date: Date(timeIntervalSince1970: 0), text: AttributedString("hi"), images: [],
            webURL: URL(string: "https://h.io/@a/1"), isLiked: false, isReposted: false,
            nativeRef: .mastodon(statusID: "1")
        )

        NSPasteboard.general.clearContents()
        let copied = model.copyLink(withURL)

        XCTAssertTrue(copied)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://h.io/@a/1")
    }

    func testCopyLinkReturnsFalseWithoutWebURL() {
        let model = makeModel(FakeFeedService())
        XCTAssertFalse(model.copyLink(TestFactory.feedPost())) // no webURL
    }

    func testReportAccountForwardsToService() async throws {
        let fake = FakeFeedService()
        let model = makeModel(fake)

        try await model.report(accountID: "did:plc:abc", reason: .harassment, comment: "stop")

        XCTAssertEqual(fake.reportAccountCalls.count, 1)
        XCTAssertEqual(fake.reportAccountCalls.first?.id, "did:plc:abc")
        XCTAssertEqual(fake.reportAccountCalls.first?.reason, .harassment)
        XCTAssertEqual(fake.reportAccountCalls.first?.comment, "stop")
    }

    func testEditAffordanceGatedToOwnMastodonPosts() {
        let store = AccountStore()
        store.mastodonUsername = "me@h.io"
        store.blueskyHandle = "me.bsky.social"
        let panel = FeedPanelModel(target: .mastodon, store: store) { _, _ in FakeFeedService() }

        let ownMastodon = TestFactory.feedPost(target: .mastodon, authorHandle: "@me@h.io")
        let othersMastodon = TestFactory.feedPost(target: .mastodon, authorHandle: "@bob@h.io")
        let ownBluesky = TestFactory.feedPost(target: .bluesky, authorHandle: "@me.bsky.social",
                                              authorID: "me.bsky.social")

        XCTAssertNotNil(postEditActions(for: ownMastodon, panel)) // editable
        XCTAssertNil(postEditActions(for: othersMastodon, panel)) // not yours
        XCTAssertNil(postEditActions(for: ownBluesky, panel)) // Bluesky has no edit
    }
}
