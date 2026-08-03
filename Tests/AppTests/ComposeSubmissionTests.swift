import XCTest
@testable import CrossPost

@MainActor
final class ComposeSubmissionTests: XCTestCase {
    private func makeModel() -> ComposeModel {
        ComposeModel(store: AccountStore())
    }

    private func result(_ target: PostTarget, _ outcome: PostResult.Outcome) -> PostResult {
        PostResult(target: target, outcome: outcome)
    }

    private let posted = [PostedItem(url: "https://x/1", ref: .mastodon(statusID: "1"))]

    // MARK: submit() — the button/keyboard path

    private func model(
        with recorder: PosterRecorder,
        findUnreadablePost: @escaping UnreadablePostFinder =
            { OutgoingImageValidation.firstUnreadablePost($0) }
    ) -> ComposeModel {
        ComposeModel(
            store: AccountStore(),
            findUnreadablePost: findUnreadablePost
        ) { recorder.make($0, $1) }
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

    func testSubmitValidatesAttachmentDataOffMainActor() async {
        let recorder = PosterRecorder()
        let probe = ComposeValidationProbe(result: nil)
        let model = model(with: recorder) { probe.validate($0) }
        model.thread[0].text = "hi"
        model.thread[0].attachments = [
            Attachment(imageData: TestFactory.pngData())
        ]

        await model.submit()

        XCTAssertFalse(probe.ranOnMainThread)
        XCTAssertEqual(recorder.requestedTargets.count, 1)
    }

    func testCancelledAttachmentValidationDoesNotPublishOrReportError() async {
        let recorder = PosterRecorder()
        let probe = ComposeValidationProbe(result: 0, blocks: true)
        let model = model(with: recorder) { probe.validate($0) }
        model.thread[0].text = "hi"
        model.thread[0].attachments = [Attachment(imageData: Data([0x00]))]

        let submission = Task { await model.submit() }
        await waitUntil { probe.hasEntered }
        submission.cancel()
        probe.release()
        await submission.value

        XCTAssertTrue(probe.observedCancellation)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(recorder.requestedTargets.isEmpty)
        XCTAssertEqual(model.thread[0].text, "hi")
        XCTAssertFalse(model.isPosting)
    }

    func testSubmitWithNoPostableContentSkipsAttachmentValidation() async {
        let recorder = PosterRecorder()
        let probe = ComposeValidationProbe(result: nil)
        let model = model(with: recorder) { probe.validate($0) }

        await model.submit()

        XCTAssertFalse(probe.hasEntered)
        XCTAssertTrue(recorder.requestedTargets.isEmpty)
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
            result(.mastodon, .failure(message: "no account"))
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
            result(.mastodon, .failure(message: "no account"))
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
                                 ref: .bluesky(uri: "at://2", cid: "c2", rootURI: "at://1", rootCID: "c1"))])
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

private final class ComposeValidationProbe: @unchecked Sendable {
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

    var hasEntered: Bool { lock.withLock { entered } }
    var ranOnMainThread: Bool { lock.withLock { mainThread } }
    var observedCancellation: Bool { lock.withLock { cancelled } }

    func validate(_ attachmentDataByPost: [[Data]]) -> Int? {
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
