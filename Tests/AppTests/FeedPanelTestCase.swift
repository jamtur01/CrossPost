@testable import CrossPost
import XCTest

@MainActor
class FeedPanelTestCase: XCTestCase {
    override func tearDown() async throws {
        let store = AccountStore()
        store.mastodonInstanceURL = ""
        store.mastodonUsername = ""
        store.blueskyHandle = ""
        try await super.tearDown()
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
