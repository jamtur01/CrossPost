@testable import CrossPost
import XCTest

@MainActor
final class ComposeCompletionTests: XCTestCase {
    func testSuccessfulPublicationClearsConfirmationAndCountsAfterFiveSeconds() async throws {
        let model = ComposeModel(store: AccountStore())
        model.thread[0].text = "Published post"
        model.handleCompletion(successes)

        XCTAssertEqual(model.completionMessage, "Posted successfully.")
        XCTAssertEqual(model.publicationStatus(for: .mastodon), "Mastodon: 1 posted")
        XCTAssertEqual(model.publicationStatus(for: .bluesky), "Bluesky: 1 posted")
        model.thread[0].text = "Next draft"

        try await Task.sleep(for: .milliseconds(5100))

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

    private var successes: [PostResult] {
        PostTarget.allCases.map {
            PostResult(target: $0, outcome: .success(posted: [PostedItem(url: "https://example/1")]))
        }
    }
}
