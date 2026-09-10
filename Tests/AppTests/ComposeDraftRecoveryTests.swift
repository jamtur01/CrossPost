@testable import CrossPost
import XCTest

@MainActor
final class ComposeDraftRecoveryTests: XCTestCase {
    private var directory: URL!
    private var draftStore: DraftStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        draftStore = DraftStore(url: directory.appending(path: "draft.plist"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testDraftRestoresTextImagesAltTextTargetsAndAudience() {
        let model = ComposeModel(store: AccountStore(), draftStore: draftStore)
        model.thread = [DraftPost(text: "Draft", attachments: [
            Attachment(imageData: TestFactory.pngData(), altText: "A picture")
        ])]
        model.selectedTargets = [.mastodon]
        model.visibility = .private
        XCTAssertTrue(model.flushDraft())

        let restored = ComposeModel(store: AccountStore(), draftStore: draftStore)
        XCTAssertEqual(restored.thread, model.thread)
        XCTAssertEqual(restored.selectedTargets, [.mastodon])
        XCTAssertEqual(restored.visibility, .private)
    }

    func testPartialThreadResumesAfterRelaunchWithoutDuplicatingPublishedPost() async {
        let account = AccountStore()
        let landed = PostedItem(url: "https://example.com/1", ref: .mastodon(statusID: "1"))
        let model = ComposeModel(store: account, draftStore: draftStore)
        model.selectedTargets = [.mastodon]
        model.thread = [DraftPost(text: "First"), DraftPost(text: "Second")]
        model.handleCompletion([PostResult(target: .mastodon, outcome:
            .partial(posted: [landed], failedIndex: 1, message: "Offline"))])
        let poster = FakePoster(target: .mastodon)
        let restored = ComposeModel(store: account, draftStore: draftStore, makePosters: { _, _ in [poster] })

        await restored.submit()

        XCTAssertEqual(poster.postedThreads.first?.map(\.text), ["Second"])
        XCTAssertEqual(poster.continuedFrom.first, landed.ref)
        let reopened = ComposeModel(store: account, draftStore: draftStore)
        XCTAssertTrue(reopened.thread[0].isEmpty)
    }

    func testEditedPublishedPrefixRemainsLockedAfterRelaunch() {
        let account = AccountStore()
        let model = ComposeModel(store: account, draftStore: draftStore)
        model.thread = [DraftPost(text: "First"), DraftPost(text: "Second")]
        model.handleCompletion([PostResult(target: .bluesky, outcome:
            .partial(posted: [PostedItem(url: nil)], failedIndex: 1, message: "Offline"))])
        model.thread[0].text = "Edited first"
        XCTAssertTrue(model.flushDraft())

        let restored = ComposeModel(store: account, draftStore: draftStore)
        XCTAssertEqual(restored.lockReason(.bluesky), .prefixEdited)
    }

    func testInterruptedPublicationCannotBeBlindlyRetried() async {
        let model = ComposeModel(store: AccountStore(), draftStore: draftStore)
        model.thread[0].text = "Possibly published"
        model.pendingTargets = [.bluesky]
        model.selectedTargets = [.bluesky]
        XCTAssertTrue(model.flushDraft())
        let recorder = PosterRecorder()
        let restored = ComposeModel(
            store: AccountStore(), draftStore: draftStore, makePosters: { recorder.make($0, $1) }
        )

        await restored.submit()

        XCTAssertEqual(restored.lockReason(.bluesky), .interrupted)
        XCTAssertTrue(recorder.requestedTargets.isEmpty)
        XCTAssertNotNil(restored.errorMessage)
    }

    func testCorruptArchiveIsPreservedUntilExplicitReset() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("Unreadable draft".utf8)
        try corrupt.write(to: draftStore.url)
        let model = ComposeModel(store: AccountStore(), draftStore: draftStore)
        model.thread[0].text = "New text"

        XCTAssertFalse(model.flushDraft())
        XCTAssertNotNil(model.draftError)
        XCTAssertEqual(try Data(contentsOf: draftStore.url), corrupt)

        model.startNewDraft()
        XCTAssertNil(model.draftError)
        XCTAssertTrue(try XCTUnwrap(draftStore.load()).thread[0].isEmpty)
    }

    func testWriteFailureIsVisibleAndBlocksPosting() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "file")
        try Data().write(to: blocker)
        let invalidStore = DraftStore(url: blocker.appending(path: "draft.plist"))
        let poster = FakePoster(target: .mastodon)
        let model = ComposeModel(
            store: AccountStore(), draftStore: invalidStore, makePosters: { _, _ in [poster] }
        )
        model.thread[0].text = "Keep this"

        await model.submit()

        XCTAssertNotNil(model.draftError)
        XCTAssertTrue(poster.postedThreads.isEmpty)
        XCTAssertEqual(model.thread[0].text, "Keep this")
    }

    func testAutosavePersistsLatestEditWithoutExplicitFlush() async throws {
        let model = ComposeModel(store: AccountStore(), draftStore: draftStore)
        model.thread[0].text = "First edit"
        model.thread[0].text = "Latest edit"
        await model.draftSaveTask?.value
        XCTAssertEqual(try draftStore.load()?.thread[0].text, "Latest edit")
    }

    func testAccountChangeCannotResumeAnotherAccountsThread() {
        let account = AccountStore()
        let previousHandle = account.blueskyHandle
        defer { account.blueskyHandle = previousHandle }
        account.blueskyHandle = "first.bsky.social"
        let model = ComposeModel(store: account, draftStore: draftStore)
        model.thread = [DraftPost(text: "First"), DraftPost(text: "Second")]
        model.handleCompletion([PostResult(target: .bluesky, outcome:
            .partial(posted: [PostedItem(url: nil)], failedIndex: 1, message: "Offline"))])

        account.blueskyHandle = "second.bsky.social"
        let restored = ComposeModel(store: account, draftStore: draftStore)
        XCTAssertEqual(restored.lockReason(.bluesky), .accountChanged)
    }

    func testChangedCredentialsDuringPosterCreationPreventPublishing() async {
        let account = AccountStore(credentials: EphemeralSecretStore())
        account.blueskyAppPassword = "first"
        let poster = FakePoster(target: .bluesky)
        let model = ComposeModel(store: account, draftStore: draftStore, makePosters: { _, store in
            store.blueskyAppPassword = "second"
            return [poster]
        })
        model.selectedTargets = [.bluesky]
        model.thread[0].text = "Unsent"

        await model.submit()

        XCTAssertTrue(poster.postedThreads.isEmpty)
        XCTAssertTrue(model.pendingTargets.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    func testRefreshedLimitDoesNotLeaveAnInterruptedPublication() async {
        let account = AccountStore()
        let oldLimit = account.mastodonMaxChars
        defer { account.mastodonMaxChars = oldLimit }
        account.mastodonMaxChars = 500
        let poster = FakePoster(target: .mastodon)
        let model = ComposeModel(store: account, draftStore: draftStore, makePosters: { _, store in
            store.mastodonMaxChars = 3
            return [poster]
        })
        model.selectedTargets = [.mastodon]
        model.thread[0].text = "Too long"
        await model.submit()

        XCTAssertTrue(poster.postedThreads.isEmpty)
        XCTAssertNil(model.lockReason(.mastodon))
        XCTAssertTrue(model.pendingTargets.isEmpty)
        XCTAssertNotNil(model.blockedIssues)
        model.thread[0].text = "OK"
        await model.submit()
        XCTAssertEqual(poster.postedThreads.count, 1)
    }

    func testVerifiedAccountOwnsSavedPublication() async {
        let account = AccountStore()
        let oldUsername = account.mastodonUsername
        defer { account.mastodonUsername = oldUsername }
        account.mastodonUsername = ""
        let poster = FakePoster(target: .mastodon)
        poster.result = .failure(ThreadPostError(
            posted: [PostedItem(url: nil, ref: .mastodon(statusID: "1"))],
            failedIndex: 1, underlying: FakePostError.boom
        ))
        let model = ComposeModel(store: account, draftStore: draftStore, makePosters: { _, store in
            store.mastodonUsername = "verified"
            return [poster]
        })
        model.selectedTargets = [.mastodon]
        model.thread = [DraftPost(text: "First"), DraftPost(text: "Second")]

        await model.submit()

        let restored = ComposeModel(store: account, draftStore: draftStore)
        XCTAssertNil(restored.lockReason(.mastodon))
    }

    func testFlushWinsOverAnEarlierAutosave() async throws {
        let model = ComposeModel(store: AccountStore(), draftStore: draftStore)
        model.thread[0].text = "Older"
        let older = SavedComposeDraft(thread: model.thread, selectedTargets: [.mastodon],
                                      visibility: .public, landed: [:], pendingTargets: [])
        let started = expectation(description: "Autosave enqueued")
        let save = Task {
            started.fulfill()
            try await draftStore.save(older)
        }
        await fulfillment(of: [started], timeout: 2)
        model.thread[0].text = "Latest"
        XCTAssertTrue(model.flushDraft())
        try await save.value
        XCTAssertEqual(try draftStore.load()?.thread[0].text, "Latest")
    }
}
