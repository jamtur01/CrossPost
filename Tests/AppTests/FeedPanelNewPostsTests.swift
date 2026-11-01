@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelNewPostsTests: FeedPanelTestCase {
    private func posts(_ ids: String...) -> [FeedPost] {
        ids.map { TestFactory.feedPost(id: $0) }
    }

    /// Serves `feed` on the next background load (a poll or stream refresh) and waits for it.
    private func arrive(_ feed: [FeedPost], _ fake: FakeFeedService, _ model: FeedPanelModel) async {
        let calls = fake.loadFeedCalls
        fake.feed = feed
        model.enqueueLoad(userInitiated: false)
        await waitUntil { fake.loadFeedCalls > calls && !model.isLoading }
    }

    private func loadedModel() async -> (FakeFeedService, FeedPanelModel) {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        await arrive(posts("a", "b", "c", "d"), fake, model)
        return (fake, model)
    }

    func testArrivalsAboveTheReaderCountUntilTheyScrollUpToThem() async {
        let (fake, model) = await loadedModel()
        model.homeScrolled(to: "c")

        await arrive(posts("n1", "n2", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 2)
        await arrive(posts("n0", "n1", "n2", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 3, "Later arrivals add to the count")

        model.homeScrolled(to: "n1")
        XCTAssertEqual(model.newPostCount, 1, "Posts the reader scrolled up to are no longer new")
        await arrive(posts("n1", "n2", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.posts.last?.id, "n0", "The merge keeps a post the page dropped, below it")
        XCTAssertEqual(model.newPostCount, 0, "A new post that's no longer above the reader stops counting")

        await arrive(posts("m", "n1", "n2", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 1)
        model.homeScrolled(to: nil)
        XCTAssertEqual(model.newPostCount, 0, "Reaching the top clears the count")
        model.stop()
    }

    func testArrivalsWhileAtTheTopDoNotCount() async {
        let (fake, model) = await loadedModel()
        await arrive(posts("n1", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 0)

        model.homeScrolled(to: FeedPanelView.topAnchor)
        await arrive(posts("n2", "n1", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 0, "The list's top anchor is the top, not a post")
        model.stop()
    }

    func testRefreshAndPillClearTheCountAndScrollToTop() async {
        let (fake, model) = await loadedModel()
        model.homeScrolled(to: "d")
        await arrive(posts("n1", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 1)

        let token = model.scrollToTopToken
        model.scrollToTop()
        XCTAssertEqual(model.newPostCount, 0)
        XCTAssertEqual(model.scrollToTopToken, token + 1)

        model.homeScrolled(to: "d")
        await arrive(posts("n2", "n1", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 1)
        fake.feed = posts("n3", "n2", "n1", "a", "b", "c", "d")
        model.refresh()
        XCTAssertEqual(model.newPostCount, 0)
        await waitUntil { model.posts.count == 7 && !model.isLoading }
        XCTAssertEqual(model.newPostCount, 0, "A refresh's own posts land at the top it scrolls to")
        XCTAssertEqual(model.scrollToTopToken, token + 2)
        model.stop()
    }

    func testSwitchingFeedsClearsTheCount() async {
        let (fake, model) = await loadedModel()
        model.homeScrolled(to: "d")
        await arrive(posts("n1", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 1)

        model.switchTo(.notifications)
        XCTAssertEqual(model.newPostCount, 0)
        await waitUntil { !model.isLoading }
        model.switchTo(.home)
        await arrive(posts("n2", "n1", "a", "b", "c", "d"), fake, model)
        XCTAssertEqual(model.newPostCount, 0, "Home comes back at the top")
        model.stop()
    }
}
