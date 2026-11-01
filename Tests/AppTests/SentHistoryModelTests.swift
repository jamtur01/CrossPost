@testable import CrossPost
import XCTest

@MainActor
final class SentHistoryModelTests: XCTestCase {
    private let landed = Date(timeIntervalSince1970: 1_800_000_000)
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var sleeps: [Duration] = []
    private var cancelledSleeps = 0
    private var fetches = 0
    private let fake = FakeFeedService()

    func testSendIsReReadSoonAfterLandingAndOnceMoreWhenItsGraceEnds() async {
        let model = makeModel { [unowned self] duration in
            sleeps.append(duration)
            clock += TimeInterval(duration.components.seconds)
        }
        fake.feed = [TestFactory.feedPost(target: .mastodon, id: "1")]
        model.record(sent)

        let found = SentHistoryModel.CopyState.status(.found(fake.feed[0]))
        await waitUntil { self.fetches == 2 && model.state(of: self.copy, now: self.clock) == found }
        XCTAssertEqual(sleeps, [.seconds(15), .seconds(106)],
                       "15s after landing, then just after the 120s grace")
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(fetches, 2, "nothing is scheduled once the grace has passed")
        XCTAssertEqual(sleeps.count, 2)
    }

    func testRefreshReplacesThePendingFollowUpAndReleasingTheModelCancelsIt() async {
        var model: SentHistoryModel? = makeModel { [unowned self] duration in
            sleeps.append(duration)
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                cancelledSleeps += 1
                throw error
            }
        }
        model?.record(sent)
        await waitUntil { self.sleeps.count == 1 }

        clock += 5
        model?.refresh()
        await waitUntil { self.cancelledSleeps == 1 && self.sleeps.count == 2 }
        XCTAssertEqual(sleeps.last, .seconds(10), "the follow-up stays anchored to the landing time")

        model = nil
        await waitUntil { self.cancelledSleeps == 2 }
        XCTAssertEqual(sleeps.count, 2)
    }

    /// Before any session has stored the Bluesky DID, the history can't tell which
    /// Bluesky copies are yours; fetching your own profile learns it.
    func testBlueskyCopiesAppearOnceTheirDIDIsLearned() async throws {
        let store = SentHistoryStore(url: URL.temporaryDirectory
            .appending(path: "history-\(UUID())/sent-history.json"))
        let uri = "at://did:plc:me/app.bsky.feed.post/a"
        try store.record(SentPost(id: UUID(), date: landed, text: "hello", postCount: 1, copies: [
            SentCopy(target: .bluesky, item: PostedItem(url: nil, ref: .bluesky(uri: uri, cid: "c", rootURI: uri,
                                                                                rootCID: "c")),
                     date: landed, account: "old-handle.bsky.social", postCount: 1)
        ]))
        fake.myProfileID = "did:plc:me"
        let model = SentHistoryModel(store: store, account: { $0 == .bluesky ? "" : nil },
                                     makeService: { [unowned self] _ in fake })
        XCTAssertTrue(model.visiblePosts.isEmpty, "unknown DID: nothing is matched yet")
        model.refresh()
        await waitUntil { model.visiblePosts.count == 1 }
    }

    private var copy: SentCopy {
        SentCopy(target: .mastodon, item: PostedItem(url: nil, ref: .mastodon(statusID: "1")), date: landed,
                 account: "me", postCount: 1)
    }

    private var sent: SentPost {
        SentPost(id: UUID(), date: landed, text: "hello", postCount: 1, copies: [copy])
    }

    private func makeModel(sleep: @escaping SentHistoryModel.Sleep) -> SentHistoryModel {
        let store = SentHistoryStore(url: URL.temporaryDirectory
            .appending(path: "history-\(UUID())/sent-history.json"))
        return SentHistoryModel(
            store: store,
            account: { $0 == .mastodon ? "me" : nil },
            makeService: { [unowned self] _ in
                fetches += 1
                return fake
            },
            now: { [unowned self] in clock },
            sleep: sleep
        )
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool, file: StaticString = #filePath,
                           line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() {
            if Date() >= deadline {
                XCTFail("condition not met within timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
