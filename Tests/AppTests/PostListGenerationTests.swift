@testable import CrossPost
import XCTest

@MainActor
final class PostListGenerationTests: FeedPanelTestCase {
    private func makeModel(_ fake: FakeFeedService) -> FeedPanelModel {
        super.makeModel(fake, target: .bluesky)
    }

    func testOldSuccessCannotReconcileOrClearNewGenerationMutation() async {
        let list = PostList(panel: makeModel(FakeFeedService()))
        let post = TestFactory.feedPost(target: .bluesky, id: "same")
        let oldGate = TestGate()
        let newGate = TestGate()
        var oldRemoteReturned = false
        list.posts = [post]

        list.mutate(
            post,
            optimistic: { $0.isLiked = true },
            action: { optimistic, _ in
                await oldGate.wait()
                oldRemoteReturned = true
                var updated = optimistic
                updated.isPinned = true
                return updated
            }
        )
        await waitUntil { oldGate.arrivals == 1 }

        list.invalidateOptimisticMutations()
        list.mutate(
            list.posts[0],
            optimistic: { _ in },
            action: { optimistic, _ in
                await newGate.wait()
                var updated = optimistic
                updated.isBookmarked = true
                return updated
            }
        )
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

        list.mutate(
            post,
            optimistic: { $0.isLiked = true },
            action: { _, _ in
                await oldGate.wait()
                oldRemoteReturned = true
                throw FakeFeedService.FakeError.boom
            }
        )
        await waitUntil { oldGate.arrivals == 1 }

        list.invalidateOptimisticMutations()
        list.posts = [post]
        list.mutate(
            post,
            optimistic: { $0.isBookmarked = true },
            action: { optimistic, _ in
                await newGate.wait()
                var updated = optimistic
                updated.isPinned = true
                return updated
            }
        )
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

    func testFailureCannotOverwriteNewerReplacement() async {
        let panel = makeModel(FakeFeedService())
        let list = PostList(panel: panel)
        let post = TestFactory.feedPost(target: .bluesky, id: "same")
        let gate = TestGate()
        list.posts = [post]

        list.mutate(
            post,
            optimistic: { $0.isLiked = true },
            action: { _, _ in
                await gate.wait()
                throw FakeFeedService.FakeError.boom
            }
        )
        await waitUntil { gate.arrivals == 1 }

        var replacement = post
        replacement.isPinned = true
        list.replace(replacement)
        gate.open()
        await waitUntil { list.inFlight.isEmpty }

        XCTAssertEqual(list.posts, [replacement])
        XCTAssertNotNil(panel.actionError)
    }
}
