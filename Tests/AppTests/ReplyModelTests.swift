@testable import CrossPost
import XCTest

@MainActor
final class ReplyModelTests: XCTestCase {
    override func tearDown() {
        AccountStore().mastodonUsername = "" // don't leak the self-handle into other tests
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
            mentionHandles: ["@carol@h.io", "@bob@h.io", "@dave@h.io"]
        )
        let model = ReplyModel(post: post, store: store)
        XCTAssertEqual(model.text, "@bob@h.io @carol@h.io @dave@h.io ")
    }

    func testMastodonReplyExcludesOwnHandle() {
        let store = AccountStore()
        store.mastodonUsername = "me@h.io"
        let post = TestFactory.feedPost(
            target: .mastodon, authorHandle: "@me@h.io",
            mentionHandles: ["@carol@h.io"]
        )
        let model = ReplyModel(post: post, store: store)
        XCTAssertEqual(model.text, "@carol@h.io ")
    }

    func testReplyVisibilitySeededFromMastodonParent() {
        let post = TestFactory.feedPost(target: .mastodon, visibility: "private")
        let model = ReplyModel(post: post, store: AccountStore())
        XCTAssertEqual(model.visibility, .private) // never widens the parent's audience
    }

    func testReplyVisibilityDefaultsPublicWhenParentHasNone() {
        let post = TestFactory.feedPost(target: .bluesky) // Bluesky carries no visibility
        let model = ReplyModel(post: post, store: AccountStore())
        XCTAssertEqual(model.visibility, .public)
    }

    func testReplyForwardsVisibilityToService() async {
        let fake = FakeFeedService()
        let post = TestFactory.feedPost(target: .mastodon, visibility: "unlisted")
        let model = ReplyModel(
            post: post,
            store: AccountStore(),
            makeService: { _, _ in fake }
        )
        model.text = "sure"
        let posted = await model.send()
        XCTAssertTrue(posted)
        XCTAssertEqual(fake.replyVisibilities, [.unlisted]) // forwarded the parent's level
    }

    func testOverLimitReplyReportsFailureAndDoesNotPost() async {
        let store = AccountStore()
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(post: post, store: store)
        model.text = String(repeating: "a", count: TargetLimits.blueskyMax + 1)

        let posted = await model.send() // validation fails before any network call

        XCTAssertFalse(posted) // must NOT report success
        XCTAssertNotNil(model.blockedIssues)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.didPost)
        XCTAssertNil(model.postedURL)
    }

    func testReplyWithUnreadableImageIsRejected() async {
        let fake = FakeFeedService()
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(
            post: post,
            store: AccountStore(),
            makeService: { _, _ in fake }
        )
        model.text = "sure"
        model.attachments = [Attachment(imageData: Data([0x00, 0x01]))] // not an image

        let posted = await model.send()

        XCTAssertFalse(posted)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.didPost)
        XCTAssertNil(model.postedURL)
    }

    func testReplyValidatesAttachmentDataOffMainActor() async {
        let fake = FakeFeedService()
        let probe = ReplyValidationProbe(result: nil)
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(
            post: post,
            store: AccountStore(),
            findUnreadablePost: { probe.validate($0) },
            makeService: { _, _ in fake }
        )
        model.text = "sure"
        model.attachments = [Attachment(imageData: TestFactory.pngData())]

        let posted = await model.send()

        XCTAssertTrue(posted)
        XCTAssertFalse(probe.ranOnMainThread)
    }

    func testCancelledReplyValidationDoesNotPostOrReportError() async {
        let fake = FakeFeedService()
        let probe = ReplyValidationProbe(result: 0, blocks: true)
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(
            post: post,
            store: AccountStore(),
            findUnreadablePost: { probe.validate($0) },
            makeService: { _, _ in fake }
        )
        model.text = "sure"
        model.attachments = [Attachment(imageData: Data([0x00]))]

        let reply = Task { await model.send() }
        await waitUntil { probe.hasEntered }
        reply.cancel()
        probe.release()
        let posted = await reply.value

        XCTAssertFalse(posted)
        XCTAssertTrue(probe.observedCancellation)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.didPost)
        XCTAssertNil(model.postedURL)
        XCTAssertTrue(fake.replyVisibilities.isEmpty)
        XCTAssertFalse(model.isSending)
    }

    func testCanceledReplyProviderCompletionDoesNotPublishSuccess() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        fake.replyDelay = { await gate.wait() }
        let model = ReplyModel(
            post: TestFactory.feedPost(target: .bluesky),
            store: AccountStore(),
            makeService: { _, _ in fake }
        )
        model.text = "sure"

        let reply = Task { await model.send() }
        await waitUntil { gate.arrivals == 1 }
        reply.cancel()
        gate.open()
        await waitUntil { fake.replyCompletions == 1 }
        let posted = await reply.value

        XCTAssertFalse(posted)
        XCTAssertFalse(model.didPost)
        XCTAssertNil(model.postedURL)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isSending)
    }

    func testEmptyReplySkipsAttachmentValidation() async {
        let fake = FakeFeedService()
        let probe = ReplyValidationProbe(result: nil)
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(
            post: post,
            store: AccountStore(),
            findUnreadablePost: { probe.validate($0) },
            makeService: { _, _ in fake }
        )

        let posted = await model.send()

        XCTAssertFalse(posted)
        XCTAssertFalse(probe.hasEntered)
        XCTAssertTrue(fake.replyVisibilities.isEmpty)
    }

    func testImageOnlyReplyPostsAndRefreshesOnce() async {
        let fake = FakeFeedService()
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(
            post: post,
            store: AccountStore(),
            makeService: { _, _ in fake }
        )
        model.text = "" // no text…
        model.attachments = [Attachment(imageData: TestFactory.pngData(), altText: "alt")] // …just an image

        var refreshCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .crossPostDidPost, object: nil, queue: nil
        ) { _ in refreshCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        let posted = await model.send()

        XCTAssertTrue(posted) // image-only reply is allowed
        XCTAssertNil(model.blockedIssues)
        XCTAssertTrue(model.didPost)
        XCTAssertEqual(model.postedURL, URL(string: "https://example/reply"),
                       "the permalink is a real URL now, never a sentinel string")
        XCTAssertEqual(refreshCount, 1)
    }

    func testSendIgnoresReentrantCallWhileSending() async {
        let fake = FakeFeedService()
        let post = TestFactory.feedPost(target: .bluesky)
        let model = ReplyModel(
            post: post,
            store: AccountStore(),
            makeService: { _, _ in fake }
        )
        model.text = "hi"
        model.isSending = true // simulate a send already in flight

        let posted = await model.send()

        XCTAssertFalse(posted)
        XCTAssertTrue(fake.replyVisibilities.isEmpty, "a reentrant send must not post again")
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
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

private final class ReplyValidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let result: Int?
    private let blocks: Bool
    private var entered = false
    private var mainThread = true
    private var cancelled = false

    init(result: Int?, blocks: Bool = false) {
        self.result = result
        self.blocks = blocks
    }

    var hasEntered: Bool {
        lock.withLock { entered }
    }

    var ranOnMainThread: Bool {
        lock.withLock { mainThread }
    }

    var observedCancellation: Bool {
        lock.withLock { cancelled }
    }

    func validate(_: [[Data]]) -> Int? {
        lock.withLock {
            entered = true
            mainThread = Thread.isMainThread
        }
        if blocks {
            _ = releaseSemaphore.wait(timeout: .now() + 2)
        }
        lock.withLock { cancelled = Task.isCancelled }
        return result
    }

    func release() {
        releaseSemaphore.signal()
    }
}
