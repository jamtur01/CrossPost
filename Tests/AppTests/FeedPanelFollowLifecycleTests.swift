@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelFollowLifecycleTests: FeedPanelTestCase {
    func testCanceledRelationshipMutationDoesNotPublishResult() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        fake.setFollowingDelay = { await gate.wait() }
        let model = makeModel(fake)
        let mutation = Task {
            try await model.setFollowing(
                true,
                for: "actor",
                current: AccountRelationship(isFollowing: false)
            )
        }
        await waitUntil { fake.setFollowingCalls == ["actor:true"] }

        mutation.cancel()
        gate.open()

        if case let .failure(error) = await mutation.result {
            XCTAssertTrue(error is CancellationError)
        } else {
            XCTFail("the canceled relationship mutation must not publish")
        }
        XCTAssertFalse(model.isFollowing("actor"))
    }

    func testCredentialRestartRejectsRelationshipMutationResult() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        fake.setFollowingDelay = { await gate.wait() }
        let model = makeModel(fake)
        let mutation = Task {
            try await model.setFollowing(
                true,
                for: "actor",
                current: AccountRelationship(isFollowing: false)
            )
        }
        await waitUntil { fake.setFollowingCalls == ["actor:true"] }

        model.restartAfterCredentialsChange()
        gate.open()

        if case let .failure(error) = await mutation.result {
            XCTAssertTrue(error is CancellationError)
        } else {
            XCTFail("the old-account relationship result must be rejected")
        }
        XCTAssertFalse(model.isFollowing("actor"))
        model.stop()
    }

    func testSupersededFollowStateBatchCannotMergeLateResult() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        let model = makeModel(fake)
        let notification = FeedNotification.fixture(
            id: "notification",
            date: Date(),
            actorID: "actor"
        )
        fake.relationshipsToReturn = ["actor": AccountRelationship(isFollowing: true)]
        fake.relationshipsDelay = { await gate.wait() }
        model.refreshFollowStates(for: [notification], service: fake)
        await waitUntil { gate.arrivals == 1 }

        fake.relationshipsDelay = nil
        fake.relationshipsToReturn = ["actor": AccountRelationship(isFollowing: false)]
        model.refreshFollowStates(for: [notification], service: fake)
        await waitUntil { fake.relationshipsRequests.count == 2 && model.followStateTask == nil }

        gate.open()
        await waitUntil { fake.relationshipsCompletions == 2 }

        XCTAssertFalse(model.isFollowing("actor"))
    }

    func testInitialFollowStateBatchPublishesFollowingActor() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let notification = FeedNotification.fixture(
            id: "notification",
            date: Date(),
            actorID: "actor"
        )
        fake.relationshipsToReturn = ["actor": AccountRelationship(isFollowing: true)]

        model.refreshFollowStates(for: [notification], service: fake)
        await waitUntil { model.followStateTask == nil }

        XCTAssertTrue(model.isFollowing("actor"))
    }

    func testMutationDuringBatchPreservesUnrelatedFollowStates() async throws {
        let fake = FakeFeedService()
        let gate = TestGate()
        let model = makeModel(fake)
        let notifications = [
            FeedNotification.fixture(id: "one", date: Date(), actorID: "mutated"),
            FeedNotification.fixture(id: "two", date: Date(), actorID: "other")
        ]
        fake.relationshipsToReturn = [
            "mutated": AccountRelationship(isFollowing: false),
            "other": AccountRelationship(isFollowing: true)
        ]
        fake.relationshipsDelay = { await gate.wait() }
        model.refreshFollowStates(for: notifications, service: fake)
        await waitUntil { gate.arrivals == 1 }

        _ = try await model.setFollowing(
            true,
            for: "mutated",
            current: AccountRelationship(isFollowing: false)
        )
        gate.open()
        await waitUntil { fake.relationshipsCompletions == 1 }

        XCTAssertTrue(model.isFollowing("mutated"))
        XCTAssertTrue(model.isFollowing("other"))
    }

    func testFollowStateBatchStartedDuringMutationCannotOverwriteSuccess() async throws {
        let fake = FakeFeedService()
        let mutationGate = TestGate()
        let batchGate = TestGate()
        fake.setFollowingDelay = { await mutationGate.wait() }
        let model = makeModel(fake)
        let mutation = Task {
            try await model.setFollowing(
                true,
                for: "actor",
                current: AccountRelationship(isFollowing: false)
            )
        }
        await waitUntil { fake.setFollowingCalls == ["actor:true"] }

        fake.relationshipsToReturn = ["actor": AccountRelationship(isFollowing: false)]
        fake.relationshipsDelay = { await batchGate.wait() }
        let notification = FeedNotification.fixture(
            id: "notification",
            date: Date(),
            actorID: "actor"
        )
        model.refreshFollowStates(for: [notification], service: fake)
        await waitUntil { batchGate.arrivals == 1 }

        mutationGate.open()
        _ = try await mutation.value
        XCTAssertTrue(model.isFollowing("actor"))

        batchGate.open()
        await waitUntil { fake.relationshipsCompletions == 1 }
        XCTAssertTrue(model.isFollowing("actor"))
    }

    func testFollowStateBatchFailureIsSurfaced() async {
        let fake = FakeFeedService()
        fake.failRelationship = true
        let model = makeModel(fake)
        let notification = FeedNotification.fixture(
            id: "notification",
            date: Date(),
            actorID: "actor"
        )

        model.refreshFollowStates(for: [notification], service: fake)
        await waitUntil { model.followStateTask == nil }

        XCTAssertNotNil(model.actionError)
    }
}
