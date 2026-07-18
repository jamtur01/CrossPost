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
    private let posted = [PostedItem(url: "https://x/1", ref: .mastodon(statusID: "1"))]
    private let posted2 = [PostedItem(url: "https://x/1", ref: .mastodon(statusID: "1")),
                           PostedItem(url: "https://x/2", ref: .mastodon(statusID: "2"))]

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

    func testFullySentTargetIsLockedAndPartialStaysResumable() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        // Mastodon landed both posts (fully sent); Bluesky landed only the 1st.
        model.handleCompletion([
            result(.mastodon, .success(posted: posted2)),
            result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "boom")),
        ])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.thread.count, 2)          // draft kept, not cleared
        // Mastodon is fully sent → deselected and locked.
        XCTAssertFalse(model.selectedTargets.contains(.mastodon))
        XCTAssertEqual(model.lockReason(.mastodon), .fullySent)
        // Bluesky has an unsent 2nd post → stays selected and resumable, not locked.
        XCTAssertTrue(model.selectedTargets.contains(.bluesky))
        XCTAssertFalse(model.isLocked(.bluesky))
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

    func testEditingTheUnsentSuffixKeepsTargetResumable() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        // Only the 1st post landed on Bluesky.
        model.handleCompletion([result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "x"))])
        XCTAssertFalse(model.isLocked(.bluesky))           // resumable: 2nd post unsent

        model.thread[1].text = "second, edited"            // edit only the unsent suffix
        XCTAssertFalse(model.isLocked(.bluesky))           // still resumable, prefix intact
    }

    func testEditingAnAlreadyLandedPostLocksTheTarget() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        model.handleCompletion([result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "x"))])
        XCTAssertFalse(model.isLocked(.bluesky))           // resumable before the edit

        model.thread[0].text = "first, edited"             // edit the already-published 1st post
        XCTAssertEqual(model.lockReason(.bluesky), .prefixEdited)
    }

    func testRemovingALandedPostLocksTheTarget() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        // Bluesky landed both posts; Mastodon failed so the draft is kept.
        model.handleCompletion([
            result(.bluesky, .success(posted: posted2)),
            result(.mastodon, .failure(message: "no account")),
        ])
        XCTAssertEqual(model.lockReason(.bluesky), .fullySent)

        model.removePost(at: 1)                            // remove the 2nd (landed) post
        // The thread no longer matches the landed prefix → reposting [first] would
        // duplicate it, so the target is locked as edited, never resent.
        XCTAssertEqual(model.lockReason(.bluesky), .prefixEdited)
    }

    func testTogglingAFullySentTargetIsRefusedWithMessage() {
        let model = makeModel()
        model.thread[0].text = "only post"
        // Bluesky fully sent; Mastodon failed so the draft (and lock) persist.
        model.handleCompletion([
            result(.bluesky, .success(posted: posted)),
            result(.mastodon, .failure(message: "no account")),
        ])
        XCTAssertFalse(model.selectedTargets.contains(.bluesky))   // fully sent → de-selected
        model.errorMessage = nil
        model.toggle(.bluesky)                                     // re-selecting it is refused
        XCTAssertFalse(model.selectedTargets.contains(.bluesky))
        XCTAssertNotNil(model.errorMessage)
    }

    // MARK: submit() — the button/keyboard path

    private func model(with recorder: PosterRecorder) -> ComposeModel {
        ComposeModel(store: AccountStore()) { recorder.make($0, $1) }
    }

    func testValidationFailureBlocksBeforePosterCreation() async {
        let recorder = PosterRecorder()
        let model = model(with: recorder)
        model.thread[0].text = String(repeating: "a", count: TargetLimits.blueskyMax + 1)  // over Bluesky's limit

        await model.submit()

        XCTAssertNotNil(model.blockedIssues)
        XCTAssertTrue(recorder.requestedTargets.isEmpty)   // never reached poster creation
        XCTAssertFalse(model.thread[0].isEmpty)            // draft kept
    }

    func testOnlySelectedTargetsGetPosters() async {
        let recorder = PosterRecorder()
        let model = model(with: recorder)
        model.thread[0].text = "hi"
        model.toggle(.bluesky)   // leave only Mastodon selected

        await model.submit()

        XCTAssertEqual(recorder.requestedTargets, [[.mastodon]])
    }

    func testSubmitStampsChosenVisibilityOntoEveryDraft() async {
        let recorder = PosterRecorder()
        let masto = FakePoster(target: .mastodon)
        recorder.postersByTarget = [.mastodon: masto]
        let model = model(with: recorder)
        model.toggle(.bluesky)                                  // Mastodon only
        model.thread = [DraftPost(text: "one"), DraftPost(text: "two")]
        model.visibility = .private

        await model.submit()

        XCTAssertEqual(masto.postedThreads.count, 1)
        XCTAssertEqual(masto.postedThreads.first?.map(\.visibility), [.private, .private])
    }

    func testSubmitDefaultsToPublicVisibility() async {
        let recorder = PosterRecorder()
        let masto = FakePoster(target: .mastodon)
        recorder.postersByTarget = [.mastodon: masto]
        let model = model(with: recorder)
        model.toggle(.bluesky)
        model.thread[0].text = "hi"

        await model.submit()

        XCTAssertEqual(masto.postedThreads.first?.first?.visibility, .public)
    }

    func testSubmitRejectsUnreadableImageBeforePosting() async {
        let recorder = PosterRecorder()
        let masto = FakePoster(target: .mastodon)
        recorder.postersByTarget = [.mastodon: masto]
        let model = model(with: recorder)
        model.toggle(.bluesky)                                   // Mastodon only
        model.thread[0].text = "hi"
        model.thread[0].attachments = [Attachment(imageData: Data([0x00, 0x01]))]   // not an image

        await model.submit()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(masto.postedThreads.isEmpty, "an unreadable image must abort before any post")
    }

    func testSuccessClearsDraftAndPostsRefreshNotificationOnce() async {
        let recorder = PosterRecorder()
        let model = model(with: recorder)
        model.thread[0].text = "hi"

        var refreshCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .crossPostDidPost, object: nil, queue: nil) { _ in refreshCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        await model.submit()

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(model.thread.count, 1)
        XCTAssertTrue(model.thread[0].isEmpty)   // box cleared on a clean run
        XCTAssertNil(model.errorMessage)
    }

    func testPartialFailureKeepsDraftAndDeselectsOnlyLanded() async {
        let recorder = PosterRecorder()
        let bluesky = FakePoster(target: .bluesky)
        bluesky.result = .failure(FakePostError.boom)   // Bluesky fails entirely
        recorder.postersByTarget = [.bluesky: bluesky]  // Mastodon defaults to success
        let model = model(with: recorder)
        model.thread[0].text = "hi"

        await model.submit()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.thread.count, 1)
        XCTAssertFalse(model.thread[0].isEmpty)          // draft kept
        XCTAssertEqual(model.selectedTargets, [.bluesky]) // only landed Mastodon de-selected
    }

    /// The landed signature keys on text + image identity, so editing only a post's
    /// alt text must NOT mark an already-published prefix as edited — the live post
    /// is unchanged. (Guards against folding alt text into the signature.)
    func testEditingOnlyAltTextKeepsTheLandedPrefixIntact() {
        let model = makeModel()
        model.thread[0].text = "with image"
        model.thread[0].attachments = [Attachment(imageData: Data([0x1]), altText: "old")]
        // Bluesky fully landed the post; Mastodon failed so the draft is kept.
        model.handleCompletion([
            result(.bluesky, .success(posted: posted)),
            result(.mastodon, .failure(message: "no account")),
        ])
        XCTAssertEqual(model.lockReason(.bluesky), .fullySent)

        model.thread[0].attachments[0].altText = "new alt text"   // same image id
        XCTAssertEqual(model.lockReason(.bluesky), .fullySent)    // not .prefixEdited
    }

    /// The signature captures attachment identity, not just text: swapping a landed
    /// post's image for a different one (same bytes, new id) must lock the target.
    func testReplacingALandedPostsImageLocksTheTarget() {
        let model = makeModel()
        model.thread[0].text = "with image"
        model.thread[0].attachments = [Attachment(imageData: Data([0x1]), altText: "alt")]
        // Bluesky fully landed the post; Mastodon failed so the draft (and lock) persist.
        model.handleCompletion([
            result(.bluesky, .success(posted: posted)),
            result(.mastodon, .failure(message: "no account")),
        ])
        XCTAssertEqual(model.lockReason(.bluesky), .fullySent)

        model.thread[0].attachments = [Attachment(imageData: Data([0x1]), altText: "alt")]
        XCTAssertEqual(model.lockReason(.bluesky), .prefixEdited,
                       "a replaced image changes the live post's content identity")
    }

    func testSubmitIgnoresReentrantCallWhileposting() async {
        let recorder = PosterRecorder()
        let model = model(with: recorder)
        model.thread[0].text = "hi"
        model.isPosting = true   // simulate a submit already in flight

        await model.submit()

        XCTAssertTrue(recorder.requestedTargets.isEmpty, "a reentrant submit must not post again")
    }

    func testSubmitDoesNothingWithNoSelectedTargets() async {
        let recorder = PosterRecorder()
        let model = model(with: recorder)
        model.thread[0].text = "hi"
        model.toggle(.mastodon); model.toggle(.bluesky)   // deselect both
        XCTAssertTrue(model.selectedTargets.isEmpty)

        await model.submit()

        XCTAssertTrue(recorder.requestedTargets.isEmpty)
        XCTAssertFalse(model.thread[0].isEmpty, "an empty-target submit must not clear the draft")
    }

    func testRetryResumesOnlyTheUnsentSuffix() async {
        let recorder = PosterRecorder()
        let bluesky = FakePoster(target: .bluesky)
        // First attempt: post 1 lands, post 2 fails mid-thread. Retry: the suffix succeeds.
        let landed1 = PostedItem(url: "https://x/1",
                                 ref: .bluesky(uri: "at://1", cid: "c1", rootURI: "at://1", rootCID: "c1"))
        bluesky.resultQueue = [
            .failure(ThreadPostError(posted: [landed1], failedIndex: 1, underlying: FakePostError.boom)),
            .success([PostedItem(url: "https://x/2",
                                 ref: .bluesky(uri: "at://2", cid: "c2", rootURI: "at://1", rootCID: "c1"))]),
        ]
        recorder.postersByTarget = [.bluesky: bluesky]
        let model = model(with: recorder)
        model.toggle(.mastodon)   // Bluesky only
        model.thread = [DraftPost(text: "first"), DraftPost(text: "second")]

        await model.submit()   // first attempt → partial, Bluesky stays selected
        XCTAssertTrue(model.selectedTargets.contains(.bluesky))
        XCTAssertFalse(model.isLocked(.bluesky))

        await model.submit()   // retry → resumes the suffix

        XCTAssertEqual(bluesky.postedThreads.count, 2)
        XCTAssertEqual(bluesky.postedThreads[0].map(\.text), ["first", "second"])  // fresh: whole thread
        XCTAssertEqual(bluesky.postedThreads[1].map(\.text), ["second"])           // retry: only the unsent post
        XCTAssertNil(bluesky.continuedFrom[0])                                     // fresh: no resume ref
        XCTAssertEqual(bluesky.continuedFrom[1], landed1.ref)                      // retry: threads onto post 1
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.thread[0].isEmpty)   // clean run after resume → box cleared
    }

    func testSubmitRefusesATargetWhosePublishedPrefixWasEdited() async {
        let recorder = PosterRecorder()
        let bluesky = FakePoster(target: .bluesky)
        let landed1 = PostedItem(url: "https://x/1",
                                 ref: .bluesky(uri: "at://1", cid: "c1", rootURI: "at://1", rootCID: "c1"))
        bluesky.result = .failure(
            ThreadPostError(posted: [landed1], failedIndex: 1, underlying: FakePostError.boom))
        recorder.postersByTarget = [.bluesky: bluesky]
        let model = model(with: recorder)
        model.toggle(.mastodon)   // Bluesky only
        model.thread = [DraftPost(text: "first"), DraftPost(text: "second")]

        await model.submit()   // post 1 lands, post 2 fails
        XCTAssertEqual(bluesky.postedThreads.count, 1)

        model.thread[0].text = "first, edited"   // edit the already-published post
        await model.submit()                     // must refuse, not resend

        XCTAssertEqual(bluesky.postedThreads.count, 1, "an edited published prefix must not be resent")
        XCTAssertNotNil(model.errorMessage)
    }
}
