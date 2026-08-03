@testable import CrossPost
import XCTest

@MainActor
final class PostListLifecycleTests: FeedPanelTestCase {
    func testCredentialRestartCannotRouteOldPostMutationToFreshService() async {
        let oldService = FakeFeedService()
        let freshService = FakeFeedService()
        let gate = TestGate()
        var builds = 0
        let store = makeStore()
        let panel = FeedPanelModel(target: .bluesky, store: store) { _, _ in
            builds += 1
            if builds == 1 {
                await gate.wait()
                return oldService
            }
            return freshService
        }
        let list = PostList(panel: panel)
        let post = TestFactory.feedPost(target: .bluesky)
        list.posts = [post]

        list.toggleLike(post)
        await waitUntil { gate.arrivals == 1 }
        panel.restartAfterCredentialsChange()
        gate.open()
        await waitUntil { list.inFlight.isEmpty }

        XCTAssertTrue(oldService.likeSetCalls.isEmpty)
        XCTAssertTrue(freshService.likeSetCalls.isEmpty)
        XCTAssertFalse(list.posts[0].isLiked)
        XCTAssertNil(panel.actionError)
        panel.stop()
    }

    func testMutationStartedAfterCredentialRestartUsesFreshService() async {
        let oldService = FakeFeedService()
        let freshService = FakeFeedService()
        var activeService = oldService
        let store = makeStore()
        let panel = FeedPanelModel(target: .bluesky, store: store) { _, _ in
            activeService
        }
        let list = PostList(panel: panel)
        let post = TestFactory.feedPost(target: .bluesky)
        list.posts = [post]

        activeService = freshService
        panel.restartAfterCredentialsChange()
        list.toggleLike(post)
        await waitUntil { list.inFlight.isEmpty }

        XCTAssertTrue(oldService.likeSetCalls.isEmpty)
        XCTAssertEqual(freshService.likeSetCalls, [true])
        XCTAssertTrue(list.posts[0].isLiked)
        panel.stop()
    }
}
