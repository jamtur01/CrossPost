@testable import CrossPost
import XCTest

@MainActor
final class ComposeModelTests: XCTestCase {
    private func makeModel() -> ComposeModel {
        ComposeModel(store: AccountStore())
    }

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

    func testRestrictedCrossPostExplainsPublicBlueskyAudience() {
        let model = makeModel()
        for visibility in [PostVisibility.private, .direct] {
            model.visibility = visibility
            XCTAssertTrue(model.audienceWarning?.contains("Bluesky will publish this publicly") == true)
        }
    }

    func testAudienceWarningOnlyAppearsForMixedRestrictedAudiences() {
        let model = makeModel()
        XCTAssertNil(model.audienceWarning)
        model.visibility = .unlisted
        XCTAssertNil(model.audienceWarning)
        model.visibility = .private
        model.selectedTargets = [.mastodon]
        XCTAssertNil(model.audienceWarning)
        model.selectedTargets = [.bluesky]
        XCTAssertNil(model.audienceWarning)
    }

    // MARK: handleCompletion — post-publish reconciliation

    func testCounterShowsNetworkWithLeastRoom() {
        let store = AccountStore()
        let previous = store.mastodonMaxChars
        defer { store.mastodonMaxChars = previous }
        let model = ComposeModel(store: store)
        store.mastodonMaxChars = 200
        XCTAssertEqual(model.counter(for: DraftPost()), PostCounter(count: 0, limit: 200, label: "Mastodon"))
        store.mastodonMaxChars = 500
        XCTAssertEqual(model.counter(for: DraftPost()).label, "Bluesky")
        store.mastodonMaxChars = 300
        XCTAssertEqual(model.counter(for: DraftPost()).label, "Both networks")

        let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")
        let post = DraftPost(text: "@pup", mentions: [MentionSpan(location: 0, length: 4, person: person)])
        XCTAssertEqual(model.counter(for: post), PostCounter(count: 4, limit: 300, label: "Mastodon"))
        model.previewTarget = .bluesky
        XCTAssertEqual(model.counter(for: post), PostCounter(count: 3, limit: 300, label: "Bluesky"))
    }

    func testDeselectingPreviewedNetworkReturnsToEdit() {
        let model = makeModel()
        model.previewTarget = .bluesky
        model.toggle(.bluesky)
        XCTAssertNil(model.previewTarget)
    }

    func testChoosingPairedAccountUpdatesMentionAndSavesPair() {
        let url = URL.temporaryDirectory.appending(path: "pairs-\(UUID()).json")
        let model = ComposeModel(store: AccountStore(), mentionPairStore: MentionPairStore(url: url))
        let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")
        let span = MentionSpan(location: 0, length: 4, person: person)
        model.thread[0] = DraftPost(text: "@pup", mentions: [span])
        model.pairing = MentionPairingRequest(draftID: model.thread[0].id, span: span, target: .bluesky)
        model.completePairing(with: MentionPerson(blueskyHandle: "lk.example.com", displayName: "Luke"))
        XCTAssertEqual(model.thread[0].mentions.first?.person.blueskyHandle, "lk.example.com")
        XCTAssertEqual(model.thread[0].mentions.first?.person.mastodonAcct, "pup@hachyderm.io")
        XCTAssertNil(model.pairing)
        XCTAssertEqual(MentionPairStore(url: url).load(),
                       [MentionPair(mastodonAcct: "pup@hachyderm.io", blueskyHandle: "lk.example.com")])
    }

    func testRepointingLandedMentionLocksThatNetwork() {
        let model = makeModel()
        let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")
        model.thread[0] = DraftPost(text: "@pup", mentions: [MentionSpan(location: 0, length: 4, person: person)])
        model.handleCompletion([result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "x"))])
        XCTAssertEqual(model.lockReason(.bluesky), .fullySent)
        model.thread[0].mentions[0].person.blueskyHandle = "lk.example.com"
        XCTAssertEqual(model.lockReason(.bluesky), .prefixEdited)
    }

    func testPartialPublicationShowsNetworkResultsAndRetryDestination() {
        let model = makeModel()
        model.thread[0].text = "Ready"
        model.handleCompletion([
            result(.mastodon, .success(posted: posted)),
            result(.bluesky, .failure(message: "Offline"))
        ])
        XCTAssertEqual(model.publicationStatus(for: .mastodon), "Mastodon: 1 posted")
        XCTAssertEqual(model.publicationStatus(for: .bluesky), "Bluesky: Failed")
        XCTAssertEqual(model.submissionLabel, "Retry Bluesky")
        model.addPost()
        model.selectedTargets = [.mastodon]
        XCTAssertEqual(model.submissionLabel, "Continue thread")
        model.startNewDraft()
        XCTAssertNil(model.publicationStatus(for: .mastodon))
        XCTAssertEqual(model.submissionLabel, "Post")
    }

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
            result(.bluesky, .success(posted: posted))
        ])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.thread.count, 1)
        XCTAssertTrue(model.thread[0].isEmpty) // box cleared on a clean run
    }

    func testSuccessfulSendPreservesEditsMadeDuringPosting() {
        let model = makeModel()
        model.thread[0].text = "Submitted text"
        let submitted = model.thread
        model.thread[0].text = "New text typed while posting"

        model.handleCompletion([result(.mastodon, .success(posted: posted))], published: submitted)

        XCTAssertEqual(model.thread[0].text, "New text typed while posting")
        XCTAssertEqual(model.lockReason(.mastodon), .prefixEdited)
    }

    func testSuccessfulSendPreservesPostsAddedDuringPosting() {
        let model = makeModel()
        model.thread[0].text = "Submitted text"
        let submitted = model.thread
        model.addPost()
        model.thread[1].text = "Continue the thread"

        model.handleCompletion([result(.mastodon, .success(posted: posted))], published: submitted)

        XCTAssertEqual(model.thread.count, 2)
        XCTAssertNil(model.lockReason(.mastodon))
    }

    func testFullySentTargetIsLockedAndPartialStaysResumable() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        // Mastodon landed both posts (fully sent); Bluesky landed only the 1st.
        model.handleCompletion([
            result(.mastodon, .success(posted: posted2)),
            result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "boom"))
        ])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.thread.count, 2) // draft kept, not cleared
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
            result(.bluesky, .partial(posted: [], failedIndex: 0, message: "boom"))
        ])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLocked(.bluesky)) // nothing landed → still retryable
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
        XCTAssertFalse(model.isLocked(.bluesky)) // resumable: 2nd post unsent

        model.thread[1].text = "second, edited" // edit only the unsent suffix
        XCTAssertFalse(model.isLocked(.bluesky)) // still resumable, prefix intact
    }

    func testEditingAnAlreadyLandedPostLocksTheTarget() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        model.handleCompletion([result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "x"))])
        XCTAssertFalse(model.isLocked(.bluesky)) // resumable before the edit

        model.thread[0].text = "first, edited" // edit the already-published 1st post
        XCTAssertEqual(model.lockReason(.bluesky), .prefixEdited)
    }

    func testRemovingALandedPostLocksTheTarget() {
        let model = makeModel()
        model.thread[0].text = "first"
        model.addPost(); model.thread[1].text = "second"
        // Bluesky landed both posts; Mastodon failed so the draft is kept.
        model.handleCompletion([
            result(.bluesky, .success(posted: posted2)),
            result(.mastodon, .failure(message: "no account"))
        ])
        XCTAssertEqual(model.lockReason(.bluesky), .fullySent)

        model.removePost(at: 1) // remove the 2nd (landed) post
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
            result(.mastodon, .failure(message: "no account"))
        ])
        XCTAssertFalse(model.selectedTargets.contains(.bluesky)) // fully sent → de-selected
        model.errorMessage = nil
        model.toggle(.bluesky) // re-selecting it is refused
        XCTAssertFalse(model.selectedTargets.contains(.bluesky))
        XCTAssertNotNil(model.errorMessage)
    }

    func testPreparedAttachmentsFollowDraftIDAfterItsIndexChanges() {
        let model = makeModel()
        model.addPost()
        let destinationID = model.thread[1].id
        let first = Attachment(imageData: TestFactory.pngData())
        let second = Attachment(imageData: TestFactory.pngData())
        model.removePost(at: 0)

        let applied = model.applyPreparedAttachments(
            ImageAttaching.PreparedResult(attachments: [first, second]),
            to: destinationID
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(model.thread[0].attachments, [first, second])
    }

    func testPreparedAttachmentsRejectRemovedDraftWithoutReportingFailure() {
        let model = makeModel()
        model.addPost()
        let removedID = model.thread[1].id
        model.removePost(at: 1)
        model.errorMessage = "Current error"

        let applied = model.applyPreparedAttachments(
            ImageAttaching.PreparedResult(
                attachments: [Attachment(imageData: Data([0x01]))],
                failedNames: ["broken.png"],
                exceededLimit: true
            ),
            to: removedID
        )

        XCTAssertFalse(applied)
        XCTAssertTrue(model.thread[0].attachments.isEmpty)
        XCTAssertEqual(model.errorMessage, "Current error")
    }

    func testPreparedAttachmentsRecheckRemainingSlotsAndPreserveOrder() {
        let model = makeModel()
        let existing = (0 ..< (TargetLimits.imageMax - 1)).map {
            Attachment(imageData: Data([UInt8($0)]))
        }
        model.thread[0].attachments = existing
        let first = Attachment(imageData: TestFactory.pngData())
        let second = Attachment(imageData: TestFactory.pngData())

        let applied = model.applyPreparedAttachments(
            ImageAttaching.PreparedResult(
                attachments: [first, second],
                failedNames: ["broken.png"]
            ),
            to: model.thread[0].id
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(model.thread[0].attachments, existing + [first])
        XCTAssertEqual(
            model.errorMessage,
            "Couldn't read broken.png. Maximum \(TargetLimits.imageMax) images per post."
        )
    }
}
