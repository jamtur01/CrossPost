import XCTest
@testable import CrossPost

@MainActor
final class ComposeModelTests: XCTestCase {
    private func makeModel() -> ComposeModel { ComposeModel(store: AccountStore()) }

    func testStartsWithOneEmptyPostAndBothTargets() {
        let model = makeModel()
        XCTAssertEqual(model.thread.count, 1)
        XCTAssertEqual(model.selectedTargets, [.mastodon, .bluesky])
        XCTAssertFalse(model.canPost)
    }

    func testCanPostRequiresTextAndTarget() {
        let model = makeModel()
        model.thread[0].text = "hi"
        XCTAssertTrue(model.canPost)

        model.selectedTargets = []
        XCTAssertFalse(model.canPost)
    }

    func testAddAndRemovePost() {
        let model = makeModel()
        model.addPost()
        XCTAssertEqual(model.thread.count, 2)
        model.removePost(at: 1)
        XCTAssertEqual(model.thread.count, 1)
    }

    func testRemoveLastRemainingPostIsIgnored() {
        let model = makeModel()
        model.removePost(at: 0)
        XCTAssertEqual(model.thread.count, 1)
    }

    func testRemoveOutOfRangeIndexIsIgnored() {
        let model = makeModel()
        model.addPost()
        model.removePost(at: 9)
        XCTAssertEqual(model.thread.count, 2)
    }

    func testToggleTarget() {
        let model = makeModel()
        model.toggle(.mastodon)
        XCTAssertEqual(model.selectedTargets, [.bluesky])
        model.toggle(.mastodon)
        XCTAssertEqual(model.selectedTargets, [.mastodon, .bluesky])
    }

    // MARK: handleCompletion — post-publish reconciliation

    private func result(_ target: PostTarget, _ outcome: PostResult.Outcome) -> PostResult {
        PostResult(target: target, outcome: outcome)
    }
    private let posted = [PostedItem(url: "https://x/1")]

    func testCleanRunClearsTheBox() {
        let model = makeModel()
        model.thread[0].text = "shipped"
        model.handleCompletion([
            result(.mastodon, .success(posted: posted)),
            result(.bluesky, .success(posted: posted)),
        ])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.thread.count, 1)
        XCTAssertTrue(model.thread[0].isEmpty)         // box cleared on a clean run
    }

    func testPartialFailureKeepsDraftAndLocksLandedTargets() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        // Mastodon landed both posts; Bluesky failed on the 2nd (1st already live).
        model.handleCompletion([
            result(.mastodon, .success(posted: posted)),
            result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "boom")),
        ])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.thread.count, 2)          // draft kept, not cleared
        // Both received content, so both are de-selected and locked against a re-post.
        XCTAssertTrue(model.selectedTargets.isEmpty)
        XCTAssertTrue(model.isLocked(.mastodon))
        XCTAssertTrue(model.isLocked(.bluesky))
    }

    func testSinglePostFailureStaysRetryable() {
        let model = makeModel()
        model.thread[0].text = "only post"
        // A single-post failure reports .partial with no landed posts.
        model.handleCompletion([
            result(.bluesky, .partial(posted: [], failedIndex: 0, message: "boom")),
        ])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLocked(.bluesky))       // nothing landed → still retryable
        XCTAssertTrue(model.selectedTargets.contains(.bluesky))
    }

    func testFullFailureLocksNothing() {
        let model = makeModel()
        model.thread[0].text = "x"
        model.handleCompletion([result(.mastodon, .failure(message: "no account"))])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLocked(.mastodon))
        XCTAssertEqual(model.thread.count, 1)
    }

    func testEditingContentReleasesTheLock() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        // Partial run keeps the draft, so the lock stays observable.
        model.handleCompletion([result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "x"))])
        XCTAssertTrue(model.isLocked(.bluesky))

        model.thread[0].text = "first, edited"            // content signature changes
        XCTAssertFalse(model.isLocked(.bluesky))
    }

    func testTogglingALockedTargetIsRefusedWithMessage() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        model.handleCompletion([result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "x"))])
        // Bluesky landed → de-selected and locked; re-selecting it is refused.
        XCTAssertFalse(model.selectedTargets.contains(.bluesky))
        model.toggle(.bluesky)
        XCTAssertFalse(model.selectedTargets.contains(.bluesky))
        XCTAssertNotNil(model.errorMessage)
    }

    /// Intended behavior: the lock keys on text + image identity, so editing only a
    /// post's alt text must NOT release a landed target's lock — re-posting the same
    /// text and images would duplicate it. (Guards against a regression that folds
    /// alt text into the content signature.)
    func testEditingOnlyAltTextKeepsTheLock() {
        let model = makeModel()
        model.thread[0].text = "with image"
        model.thread[0].attachments = [Attachment(imageData: Data([0x1]), altText: "old")]
        model.addPost(); model.thread[1].text = "second"
        model.handleCompletion([result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "x"))])
        XCTAssertTrue(model.isLocked(.bluesky))

        model.thread[0].attachments[0].altText = "new alt text"   // same image id
        XCTAssertTrue(model.isLocked(.bluesky))
    }
}
