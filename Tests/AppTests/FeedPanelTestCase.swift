@testable import CrossPost
import XCTest

@MainActor
class FeedPanelTestCase: XCTestCase {
    override func tearDown() async throws {
        TestFactory.resetAccountDefaults()
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
