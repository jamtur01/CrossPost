@testable import CrossPost
import XCTest

@MainActor
final class ComposeCompletionTests: XCTestCase {
    func testSuccessfulPublicationClearsConfirmationAndCountsAfterFiveSeconds() async {
        let model = ComposeModel(store: AccountStore())
        model.thread[0].text = "Published post"
        model.handleCompletion(successes)

        XCTAssertEqual(model.completionMessage, "Posted successfully.")
        XCTAssertEqual(model.publicationStatus(for: .mastodon), "Mastodon: 1 posted")
        XCTAssertEqual(model.publicationStatus(for: .bluesky), "Bluesky: 1 posted")
        model.thread[0].text = "Next draft"

        // Await the 5-second dismissal itself: a fixed sleep with a small margin
        // flakes when the main actor is busy under the full suite.
        let started = ContinuousClock.now
        await model.completionDismissTask?.value
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .seconds(5))

        XCTAssertNil(model.completionMessage)
        XCTAssertNil(model.publicationStatus(for: .mastodon))
        XCTAssertNil(model.publicationStatus(for: .bluesky))
        XCTAssertEqual(model.thread[0].text, "Next draft")
        XCTAssertEqual(model.selectedTargets, [.mastodon, .bluesky])
    }

    func testDismissalPreservesEditsAndPublishedThreadProgress() async {
        let model = ComposeModel(store: AccountStore())
        model.thread[0].text = "Published post"
        let published = model.thread
        model.thread[0].text = "Edited while sending"
        model.handleCompletion(successes, published: published)

        await model.completionDismissTask?.value

        XCTAssertNil(model.completionMessage)
        XCTAssertEqual(model.thread[0].text, "Edited while sending")
        XCTAssertEqual(model.lockReason(.mastodon), .prefixEdited)
        XCTAssertEqual(model.publicationStatus(for: .mastodon), "Mastodon: 1 already posted")
        XCTAssertEqual(model.landedByTarget[.mastodon]?.items.count, 1)
    }

    func testPreviousDismissalDoesNotClearNewSuccess() async {
        let model = ComposeModel(store: AccountStore())
        model.thread[0].text = "First post"
        model.handleCompletion(successes)
        let previousDismissal = model.completionDismissTask
        model.thread[0].text = "Second post"
        model.handleCompletion(successes)

        await previousDismissal?.value

        XCTAssertEqual(model.completionMessage, "Posted successfully.")
        XCTAssertEqual(model.publicationStatus(for: .mastodon), "Mastodon: 1 posted")
        model.startNewDraft()
    }

    func testPreviousDismissalPreservesPartialFailureAndRetryProgress() async {
        let model = ComposeModel(store: AccountStore())
        model.thread[0].text = "First post"
        model.handleCompletion(successes)
        let previousDismissal = model.completionDismissTask
        model.thread = [DraftPost(text: "Thread start"), DraftPost(text: "Thread end")]
        model.handleCompletion([
            PostResult(target: .mastodon, outcome: .success(posted: [
                PostedItem(url: "https://example/1"), PostedItem(url: "https://example/2")
            ])),
            PostResult(target: .bluesky, outcome: .partial(
                posted: [PostedItem(url: "https://example/2")], failedIndex: 1, message: "Offline"
            ))
        ])

        await previousDismissal?.value

        XCTAssertNil(model.completionMessage)
        XCTAssertNil(model.completionDismissTask)
        XCTAssertEqual(model.errorMessage, "Bluesky: post 2 failed — Offline")
        XCTAssertEqual(model.publicationStatus(for: .bluesky), "Bluesky: 1 posted; remaining posts failed")
        XCTAssertEqual(model.submissionLabel, "Retry Bluesky")
        XCTAssertEqual(model.lockReason(.mastodon), .fullySent)
        XCTAssertEqual(model.landedByTarget[.bluesky]?.items.count, 1)
        XCTAssertEqual(model.thread.map(\.text), ["Thread start", "Thread end"])
    }

    func testNewSubmissionClearsOldSuccessBeforeValidation() async {
        let model = ComposeModel(store: AccountStore())
        model.thread[0].text = "Published post"
        model.handleCompletion(successes)
        let previousDismissal = model.completionDismissTask
        model.thread[0].text = String(repeating: "a", count: 501)

        await model.submit()
        await previousDismissal?.value

        XCTAssertNil(model.completionMessage)
        XCTAssertNil(model.publicationStatus(for: .mastodon))
        XCTAssertNil(model.publicationStatus(for: .bluesky))
        XCTAssertFalse(model.blockedIssues?.isEmpty ?? true)
    }

    func testNewDraftCancelsPreviousDismissal() async {
        let model = ComposeModel(store: AccountStore())
        model.thread[0].text = "Published post"
        model.handleCompletion(successes)
        let previousDismissal = model.completionDismissTask
        model.startNewDraft()
        model.thread[0].text = "New draft"
        model.handleCompletion([PostResult(target: .bluesky, outcome: .failure(message: "Offline"))])

        await previousDismissal?.value

        XCTAssertNil(model.completionMessage)
        XCTAssertNil(model.completionDismissTask)
        XCTAssertEqual(model.errorMessage, "Bluesky: Offline")
        XCTAssertEqual(model.publicationStatus(for: .bluesky), "Bluesky: Failed")
        XCTAssertEqual(model.thread[0].text, "New draft")
    }

    func testSendsAreRecordedOncePerDraftAcrossARetry() throws {
        let historyStore = SentHistoryStore(url: URL.temporaryDirectory
            .appending(path: "history-\(UUID())/sent-history.json"))
        let model = ComposeModel(store: AccountStore(), historyStore: historyStore)
        model.handleCompletion([PostResult(target: .bluesky, outcome: .failure(message: "Offline"))])
        XCTAssertEqual(try historyStore.load(), [], "a send that landed nowhere isn't history")

        model.thread = [DraftPost(text: "Cross-post"), DraftPost(text: "Second")]
        let mastodon = PostedItem(url: "https://example/1", ref: .mastodon(statusID: "1"))
        let uri = "at://did:plc:me/app.bsky.feed.post/a"
        let bluesky = PostedItem(url: "https://bsky.app/a",
                                 ref: .bluesky(uri: uri, cid: "c", rootURI: uri, rootCID: "c"))
        model.handleCompletion([
            PostResult(target: .mastodon, outcome: .success(posted: [mastodon, mastodon])),
            PostResult(target: .bluesky, outcome: .partial(posted: [bluesky], failedIndex: 1, message: "Offline"))
        ])
        let partial = try XCTUnwrap(try historyStore.load().first)
        XCTAssertEqual(partial.copies.map(\.target), [.mastodon, .bluesky])
        XCTAssertEqual(partial.text, "Cross-post")
        XCTAssertEqual(partial.postCount, 2)
        XCTAssertEqual(partial.copies.map(\.postCount), [2, 1], "each copy counts only what landed")
        XCTAssertEqual(partial.copies.map(\.account), [model.store.accountKey(for: .mastodon),
                                                       model.store.accountKey(for: .bluesky)])

        model.handleCompletion([PostResult(target: .bluesky, outcome: .success(posted: [bluesky, bluesky]))])
        let history = try historyStore.load()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, partial.id)
        XCTAssertEqual(history.first?.copies.map(\.item), [mastodon, bluesky])
        XCTAssertEqual(history.first?.copies.map(\.postCount), [2, 2], "the retry updates the count")
        XCTAssertEqual(model.history.posts.map(\.id), history.map(\.id))
    }

    func testUnreadableHistoryIsReportedAndLeftUntouchedBySends() throws {
        let historyStore = SentHistoryStore(url: URL.temporaryDirectory
            .appending(path: "history-\(UUID())/sent-history.json"))
        try FileManager.default.createDirectory(at: historyStore.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let unreadable = Data("{ newer format".utf8)
        try unreadable.write(to: historyStore.url)
        let model = ComposeModel(store: AccountStore(), historyStore: historyStore)
        XCTAssertNotNil(model.history.problem)

        model.thread[0].text = "Published post"
        model.handleCompletion([PostResult(target: .mastodon, outcome: .success(
            posted: [PostedItem(url: "https://example/1", ref: .mastodon(statusID: "1"))]
        ))])
        XCTAssertEqual(try Data(contentsOf: historyStore.url), unreadable)
        XCTAssertEqual(model.history.problem, .unreadable)

        // A reset that can't move the file keeps the file and the way to try again.
        let folder = historyStore.url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        model.history.startNewHistory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        guard case .resetFailed? = model.history.problem else {
            return XCTFail("expected the failed reset to be reported")
        }
        XCTAssertTrue(model.history.problem?.offersReset ?? false)
        XCTAssertEqual(try Data(contentsOf: historyStore.url), unreadable)

        model.history.startNewHistory()
        guard case let .setAside(kept)? = model.history.problem else {
            return XCTFail("expected the unreadable file to be kept")
        }
        XCTAssertEqual(try Data(contentsOf: kept), unreadable)
        model.thread[0].text = "Next post"
        model.handleCompletion([PostResult(target: .mastodon, outcome: .success(
            posted: [PostedItem(url: "https://example/2", ref: .mastodon(statusID: "2"))]
        ))])
        XCTAssertEqual(try historyStore.load().map(\.text), ["Next post"])
        XCTAssertNil(model.history.problem)
    }

    private var successes: [PostResult] {
        PostTarget.allCases.map {
            PostResult(target: $0, outcome: .success(posted: [PostedItem(url: "https://example/1")]))
        }
    }
}
