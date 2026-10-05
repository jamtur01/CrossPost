@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelPerformanceTests: FeedPanelTestCase {
    func testRefreshDoesNotRequestHistoryAgain() async {
        let fake = FakeFeedService()
        fake.feed = [TestFactory.feedPost(id: "first")]
        let model = makeModel(fake)
        model.start()
        await waitUntil { !model.isLoading }
        model.refresh()
        await waitUntil { !model.isLoading }
        XCTAssertEqual(fake.historyRequests, [true, false])
        model.restartAfterCredentialsChange()
        await waitUntil { !model.isLoading }
        XCTAssertEqual(fake.historyRequests, [true, false, true])
        model.stop()
    }

    func testTabSwitchRetainsLoadedContentWhileRefreshing() async {
        let fake = FakeFeedService()
        let model = makeModel(fake, target: .bluesky)
        let post = TestFactory.feedPost(id: "cached")
        let notification = FeedNotification.fixture(id: "cached-note", date: Date())
        let conversation = Conversation(
            id: "cached-chat", otherName: "A", otherHandle: "a", otherID: "a",
            otherAvatarURL: nil, lastMessage: "Hello", lastDate: nil, unreadCount: 0
        )
        model.posts = [post]
        model.notifications = [notification]
        model.conversations = [conversation]

        model.switchTo(.notifications)
        XCTAssertEqual(model.notifications, [notification])
        model.switchTo(.messages)
        XCTAssertEqual(model.conversations, [conversation])

        let gate = TestGate()
        fake.loadDelay = { await gate.wait() }
        fake.feed = [TestFactory.feedPost(id: "fresh")]
        model.switchTo(.home)
        await waitUntil { gate.arrivals == 1 }
        XCTAssertEqual(model.posts, [post])
        XCTAssertTrue(model.isLoading)

        gate.open()
        await waitUntil { !model.isLoading }
        XCTAssertEqual(model.posts, fake.feed + [post])
        model.stop()
    }

    func testFailedRefreshKeepsCachedTabContent() async {
        let fake = FakeFeedService()
        fake.failLoad = true
        let model = makeModel(fake)
        let post = TestFactory.feedPost(id: "cached")
        model.posts = [post]
        model.switchTo(.notifications)
        model.switchTo(.home)
        await waitUntil { !model.isLoading }
        XCTAssertEqual(model.posts, [post])
        model.stop()
    }
}
