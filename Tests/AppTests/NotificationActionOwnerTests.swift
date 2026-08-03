@testable import CrossPost
import XCTest

@MainActor
final class NotificationActionOwnerTests: XCTestCase {
    func testPostMutationTeardownRejectsLateRollbackAndError() async {
        let owner = NotificationActionOwner()
        let gate = TestGate()
        var renderedPost = likedPost(id: "post")
        var errorMessage: String?
        var didFinish = false
        var observedCancellation = false

        let task = owner.startPostMutation(
            operation: {
                await gate.wait()
                observedCancellation = Task.isCancelled
                throw TestFailure.expected
            },
            onSuccess: { renderedPost = $0 },
            onFailure: {
                renderedPost = TestFactory.feedPost(id: "post")
                errorMessage = $0.userMessage
            },
            onFinish: { didFinish = true }
        )
        await waitUntil { gate.arrivals == 1 }

        owner.invalidate()
        gate.open()
        await task.value

        XCTAssertTrue(renderedPost.isLiked)
        XCTAssertNil(errorMessage)
        XCTAssertFalse(didFinish)
        XCTAssertTrue(observedCancellation)
    }

    func testPostSnapshotReplacementRejectsLateReconciliation() async {
        let owner = NotificationActionOwner()
        let gate = TestGate()
        let replacement = TestFactory.feedPost(id: "replacement")
        var renderedPost = likedPost(id: "original")
        var observedCancellation = false

        let task = owner.startPostMutation(
            operation: {
                await gate.wait()
                observedCancellation = Task.isCancelled
                return TestFactory.feedPost(id: "original")
            },
            onSuccess: { renderedPost = $0 },
            onFailure: { _ in XCTFail("late operation should not publish an error") },
            onFinish: {}
        )
        await waitUntil { gate.arrivals == 1 }

        owner.invalidate()
        renderedPost = replacement
        gate.open()
        await task.value

        XCTAssertEqual(renderedPost, replacement)
        XCTAssertTrue(observedCancellation)
    }

    func testFollowTeardownRejectsLateReconciliationAndError() async {
        let owner = NotificationActionOwner()
        let gate = TestGate()
        var relationship = AccountRelationship()
        var errorMessage: String?
        var didFinish = false
        var observedCancellation = false

        let task = owner.startFollow(
            operation: {
                await gate.wait()
                observedCancellation = Task.isCancelled
                throw TestFailure.expected
            },
            onSuccess: { relationship = $0 },
            onFailure: { errorMessage = $0.userMessage },
            onFinish: { didFinish = true }
        )
        await waitUntil { gate.arrivals == 1 }

        owner.invalidate()
        gate.open()
        await task.value

        XCTAssertFalse(relationship.isFollowing)
        XCTAssertNil(errorMessage)
        XCTAssertFalse(didFinish)
        XCTAssertTrue(observedCancellation)
    }

    func testFollowSnapshotReplacementRejectsLatePublication() async {
        let owner = NotificationActionOwner()
        let gate = TestGate()
        var relationship = AccountRelationship()
        var observedCancellation = false

        let task = owner.startFollow(
            operation: {
                await gate.wait()
                observedCancellation = Task.isCancelled
                return AccountRelationship(isFollowing: true)
            },
            onSuccess: { relationship = $0 },
            onFailure: { _ in XCTFail("late operation should not publish an error") },
            onFinish: {}
        )
        await waitUntil { gate.arrivals == 1 }

        owner.invalidate()
        gate.open()
        await task.value

        XCTAssertFalse(relationship.isFollowing)
        XCTAssertTrue(observedCancellation)
    }

    func testCurrentPostMutationFailureRollsBackAndPublishesError() async {
        let owner = NotificationActionOwner()
        let gate = TestGate()
        var renderedPost = likedPost(id: "post")
        var errorMessage: String?
        var didFinish = false

        let task = owner.startPostMutation(
            operation: {
                await gate.wait()
                throw TestFailure.expected
            },
            onSuccess: { renderedPost = $0 },
            onFailure: {
                renderedPost = TestFactory.feedPost(id: "post")
                errorMessage = $0.userMessage
            },
            onFinish: { didFinish = true }
        )
        await waitUntil { gate.arrivals == 1 }

        gate.open()
        await task.value

        XCTAssertFalse(renderedPost.isLiked)
        XCTAssertNotNil(errorMessage)
        XCTAssertTrue(didFinish)
    }

    func testCurrentFollowSuccessReconcilesAndFinishes() async {
        let owner = NotificationActionOwner()
        let gate = TestGate()
        var relationship = AccountRelationship()
        var didFinish = false

        let task = owner.startFollow(
            operation: {
                await gate.wait()
                return AccountRelationship(isFollowing: true)
            },
            onSuccess: { relationship = $0 },
            onFailure: { _ in XCTFail("current operation should not fail") },
            onFinish: { didFinish = true }
        )
        await waitUntil { gate.arrivals == 1 }

        gate.open()
        await task.value

        XCTAssertTrue(relationship.isFollowing)
        XCTAssertTrue(didFinish)
    }

    func testDirectTaskCancellationReleasesActionSlot() async {
        let owner = NotificationActionOwner()
        let gate = TestGate()
        var finishCount = 0

        let cancelled = owner.startFollow(
            operation: {
                await gate.wait()
                return AccountRelationship(isFollowing: true)
            },
            onSuccess: { _ in XCTFail("cancelled action should not publish success") },
            onFailure: { _ in XCTFail("cancelled action should not publish an error") },
            onFinish: { finishCount += 1 }
        )
        await waitUntil { gate.arrivals == 1 }

        cancelled.cancel()
        gate.open()
        await cancelled.value

        var replacementStarted = false
        let replacement = owner.startFollow(
            operation: {
                replacementStarted = true
                return AccountRelationship(isFollowing: true)
            },
            onSuccess: { _ in },
            onFailure: { _ in XCTFail("replacement action should not fail") },
            onFinish: { finishCount += 1 }
        )
        await replacement.value

        XCTAssertTrue(replacementStarted)
        XCTAssertEqual(finishCount, 2)
    }

    func testExternalGenerationChangeSuppressesEveryCompletionCallback() async {
        let owner = NotificationActionOwner()
        let gate = TestGate()
        var isCurrent = true
        var successCount = 0
        var failureCount = 0
        var finishCount = 0

        let stale = owner.startPostMutation(
            isCurrent: { isCurrent },
            operation: {
                await gate.wait()
                return self.likedPost(id: "post")
            },
            onSuccess: { _ in successCount += 1 },
            onFailure: { _ in failureCount += 1 },
            onFinish: { finishCount += 1 }
        )
        await waitUntil { gate.arrivals == 1 }

        isCurrent = false
        gate.open()
        await stale.value

        XCTAssertEqual(successCount, 0)
        XCTAssertEqual(failureCount, 0)
        XCTAssertEqual(finishCount, 0)
    }

    private func likedPost(id: String) -> FeedPost {
        var post = TestFactory.feedPost(id: id)
        post.isLiked = true
        post.likeCount = 1
        return post
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            await Task.yield()
        }
    }
}

private enum TestFailure: Error {
    case expected
}
