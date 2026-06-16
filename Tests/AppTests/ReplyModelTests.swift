import XCTest
@testable import CrossPost

@MainActor
final class ReplyModelTests: XCTestCase {
    override func tearDown() {
        AccountStore().mastodonUsername = ""   // don't leak the self-handle into other tests
        super.tearDown()
    }

    func testBlueskyReplyStartsEmpty() {
        let store = AccountStore()
        let post = TestFactory.feedPost(target: .bluesky, authorHandle: "@bob.bsky.social",
                                        mentionHandles: ["@carol.bsky.social"])
        let model = ReplyModel(post: post, store: store)
        XCTAssertEqual(model.text, "")
    }

    func testMastodonReplySeedsAuthor() {
        let store = AccountStore()
        store.mastodonUsername = ""
        let post = TestFactory.feedPost(target: .mastodon, authorHandle: "@bob@hachyderm.io")
        let model = ReplyModel(post: post, store: store)
        XCTAssertEqual(model.text, "@bob@hachyderm.io ")
    }

    func testMastodonReplyAddsParentMentionsDeduplicated() {
        let store = AccountStore()
        store.mastodonUsername = ""
        let post = TestFactory.feedPost(
            target: .mastodon, authorHandle: "@bob@h.io",
            mentionHandles: ["@carol@h.io", "@bob@h.io", "@dave@h.io"])
        let model = ReplyModel(post: post, store: store)
        XCTAssertEqual(model.text, "@bob@h.io @carol@h.io @dave@h.io ")
    }

    func testMastodonReplyExcludesOwnHandle() {
        let store = AccountStore()
        store.mastodonUsername = "me@h.io"
        let post = TestFactory.feedPost(
            target: .mastodon, authorHandle: "@me@h.io",
            mentionHandles: ["@carol@h.io"])
        let model = ReplyModel(post: post, store: store)
        XCTAssertEqual(model.text, "@carol@h.io ")
    }

    func testReplyVisibilitySeededFromMastodonParent() {
        let post = TestFactory.feedPost(target: .mastodon, visibility: "private")
        let model = ReplyModel(post: post, store: AccountStore())
        XCTAssertEqual(model.visibility, .private)   // never widens the parent's audience
    }

    func testReplyVisibilityDefaultsPublicWhenParentHasNone() {
        let post = TestFactory.feedPost(target: .bluesky)   // Bluesky carries no visibility
        let model = ReplyModel(post: post, store: AccountStore())
        XCTAssertEqual(model.visibility, .public)
    }

    func testReplyForwardsVisibilityToService() async {
        let fake = FakeFeedService()
        let post = TestFactory.feedPost(target: .mastodon, visibility: "unlisted")
        let model = ReplyModel(post: post, store: AccountStore()) { _, _ in fake }
        model.text = "sure"
        let posted = await model.send()
        XCTAssertTrue(posted)
        XCTAssertEqual(fake.replyVisibilities, [.unlisted])   // forwarded the parent's level
    }

    func testOverLimitReplyReportsFailureAndDoesNotPost() async {
        let store = AccountStore()
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(post: post, store: store)
        model.text = String(repeating: "a", count: TargetLimits.blueskyMax + 1)

        let posted = await model.send()   // validation fails before any network call

        XCTAssertFalse(posted)                       // must NOT report success
        XCTAssertNotNil(model.blockedIssues)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.postedURL)
    }

    func testImageOnlyReplyPostsAndRefreshesOnce() async {
        let fake = FakeFeedService()
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(post: post, store: AccountStore()) { _, _ in fake }
        model.text = ""                                   // no text…
        model.attachments = [Attachment(imageData: Data([0x1]), altText: "alt")]   // …just an image

        var refreshCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .crossPostDidPost, object: nil, queue: nil) { _ in refreshCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        let posted = await model.send()

        XCTAssertTrue(posted)                             // image-only reply is allowed
        XCTAssertNil(model.blockedIssues)
        XCTAssertNotNil(model.postedURL)
        XCTAssertEqual(refreshCount, 1)
    }
}
