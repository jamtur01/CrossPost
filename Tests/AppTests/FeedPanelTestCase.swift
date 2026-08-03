@testable import CrossPost
import XCTest

@MainActor
class FeedPanelTestCase: XCTestCase {
    override func tearDown() {
        let store = AccountStore()
        store.mastodonInstanceURL = ""
        store.mastodonUsername = ""
        store.blueskyHandle = ""
        super.tearDown()
    }

    func makeStore() -> AccountStore {
        let store = AccountStore()
        store.mastodonInstanceURL = "https://h.io"
        store.mastodonToken = "tok"
        store.blueskyHandle = "me.bsky.social"
        store.blueskyAppPassword = "pw"
        return store
    }

    func makeModel(
        _ fake: FakeFeedService,
        target: PostTarget = .mastodon
    ) -> FeedPanelModel {
        let store = makeStore()
        let model = FeedPanelModel(target: target, store: store) { _, _ in fake }
        model.applicationIsActive = { true }
        return model
    }

    func waitUntil(
        _ predicate: @MainActor () -> Bool,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() >= deadline {
                XCTFail("condition not met within timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

@MainActor
final class FeedPanelGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0
    private(set) var departures = 0

    func wait() async {
        arrivals += 1
        await withCheckedContinuation { waiters.append($0) }
        departures += 1
    }

    func open() {
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
