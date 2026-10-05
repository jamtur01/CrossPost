@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelLiveRefreshTests: FeedPanelTestCase {
    func testStreamBurstRefreshesOnlyAffectedContentOncePerWindow() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let id = UUID()
        let gate = TestGate()
        model.liveTaskID = id
        model.liveRefreshDelay = { await gate.wait() }

        for _ in 0 ..< 100 {
            XCTAssertTrue(model.receiveLiveUpdate(.home, ownedBy: id))
        }
        await waitUntil { gate.arrivals == 1 }
        XCTAssertEqual(fake.loadFeedCalls, 0)
        gate.open()
        await waitUntil { fake.loadFeedCalls == 1 && !model.isLoading }
        XCTAssertEqual(fake.unreadCountCalls, 0, "Home events do not change notification badges")

        XCTAssertTrue(model.receiveLiveUpdate(.notifications, ownedBy: id))
        await waitUntil { gate.arrivals == 2 }
        gate.open()
        await waitUntil { fake.unreadCountCalls == 1 }
        XCTAssertEqual(fake.loadFeedCalls, 1, "Notification events do not reload Home")
        model.stop()
    }

    func testStopCancelsBufferedUpdatesAndRejectsOldStreamEvents() async {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let id = UUID()
        let gate = TestGate()
        model.liveTaskID = id
        model.liveRefreshDelay = { await gate.wait() }
        XCTAssertTrue(model.receiveLiveUpdate(.home, ownedBy: id))
        await waitUntil { gate.arrivals == 1 }
        model.stop()
        gate.open()
        await Task.yield()
        XCTAssertFalse(model.receiveLiveUpdate(.notifications, ownedBy: id))
        XCTAssertEqual(fake.loadFeedCalls, 0)
        XCTAssertEqual(fake.unreadCountCalls, 0)
    }

    func testUnchangedNotificationsReuseFollowStatesAndReadAcknowledgement() async {
        let fake = FakeFeedService()
        fake.notificationsToReturn = [.fixture(id: "note", date: Date())]
        fake.relationshipsToReturn = ["a": AccountRelationship(isFollowing: true)]
        let model = makeModel(fake)
        model.switchTo(.notifications)
        await waitUntil { !model.isLoading && model.followStateTask == nil }
        XCTAssertEqual(fake.markedReadCalls.count, 1)
        XCTAssertEqual(fake.relationshipsRequests.count, 1)

        model.refresh()
        await waitUntil { !model.isLoading && model.followStateTask == nil }
        XCTAssertEqual(fake.markedReadCalls.count, 1)
        XCTAssertEqual(fake.relationshipsRequests.count, 1)

        model.followStateDates["a"] = .distantPast
        model.unreadCount = 1
        model.refresh()
        await waitUntil { !model.isLoading && model.followStateTask == nil }
        XCTAssertEqual(fake.markedReadCalls.count, 2)
        XCTAssertEqual(fake.relationshipsRequests.count, 2)
        model.stop()
    }
}
