import XCTest
@testable import CrossPost

final class PostValidatorTests: XCTestCase {
    private let limits = TargetLimits(mastodonMax: 500)

    func testWithinLimitsHasNoIssues() {
        let thread = [DraftPost(text: "hello world")]
        let issues = PostValidator.validate(thread: thread, targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertTrue(issues.isEmpty)
    }

    func testGraphemeCountsEmojiAsOne() {
        // Family emoji is one grapheme cluster but many scalars/UTF-16 units.
        XCTAssertEqual(PostValidator.graphemeCount("👨‍👩‍👧‍👦"), 1)
    }

    func testTooLongForBlueskyOnly() {
        let text = String(repeating: "a", count: 350) // > 300, < 500
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertEqual(issues, [.tooLong(postIndex: 0, target: .bluesky, count: 350, limit: 300)])
    }

    func testBlueskyByteLimitCatchesMultibyteText() {
        // Bluesky enforces maxLength: 3000 UTF-8 bytes alongside maxGraphemes: 300.
        // A family emoji is 1 grapheme but 25 bytes: 121 of them pass the grapheme
        // check (121 ≤ 300) yet exceed the byte limit (3025 > 3000).
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 121)
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertEqual(issues, [.tooLongBytes(postIndex: 0, target: .bluesky, count: 3025, limit: 3000)])
    }

    func testBlueskyExactly3000BytesIsAllowed() {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 120) // 120 × 25 bytes = 3000
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.bluesky], limits: limits)
        XCTAssertTrue(issues.isEmpty)
    }

    func testOverBothLimitsReportsOnlyGraphemeIssue() {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 301) // over 300 graphemes and 3000 bytes
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.bluesky], limits: limits)
        XCTAssertEqual(issues, [.tooLong(postIndex: 0, target: .bluesky, count: 301, limit: 300)])
    }

    func testExactlyAtLimitIsAllowed() {
        let text = String(repeating: "a", count: 300)
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.bluesky], limits: limits)
        XCTAssertTrue(issues.isEmpty)
    }

    func testEmptyPostIsAnIssue() {
        let issues = PostValidator.validate(thread: [DraftPost(text: "   ")],
                                            targets: [.bluesky], limits: limits)
        XCTAssertEqual(issues, [.empty(postIndex: 0)])
    }

    func testPostWithOnlyImageIsNotEmpty() {
        let post = DraftPost(text: "", attachments: [Attachment(imageData: Data([0x1]), altText: "x")])
        let issues = PostValidator.validate(thread: [post], targets: [.bluesky], limits: limits)
        XCTAssertTrue(issues.isEmpty)
    }

    func testTooManyImagesIsAnIssuePerTarget() {
        let attachments = (0..<5).map { _ in Attachment(imageData: Data([0x1])) }
        let post = DraftPost(text: "images", attachments: attachments)
        let issues = PostValidator.validate(thread: [post], targets: [.bluesky], limits: limits)
        XCTAssertEqual(issues, [.tooManyImages(postIndex: 0, target: .bluesky, count: 5, limit: 4)])
    }

    func testAltTextOverMastodonLimitIsAnIssue() {
        // 1600 chars: over Mastodon's 1500 but under Bluesky's 2000.
        let alt = String(repeating: "a", count: 1600)
        let post = DraftPost(text: "x", attachments: [Attachment(imageData: Data([0x1]), altText: alt)])
        let issues = PostValidator.validate(thread: [post],
                                            targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertEqual(issues, [.altTextTooLong(postIndex: 0, imageIndex: 0,
                                                target: .mastodon, count: 1600, limit: 1500)])
    }

    func testAltTextOverBothLimitsReportsPerTargetAndImage() {
        let alt = String(repeating: "a", count: 2100) // over both 1500 and 2000
        let attachments = [Attachment(imageData: Data([0x1])),                       // no alt — fine
                           Attachment(imageData: Data([0x2]), altText: alt)]         // image index 1
        let post = DraftPost(text: "x", attachments: attachments)
        let issues = PostValidator.validate(thread: [post],
                                            targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertEqual(issues, [
            .altTextTooLong(postIndex: 0, imageIndex: 1, target: .mastodon, count: 2100, limit: 1500),
            .altTextTooLong(postIndex: 0, imageIndex: 1, target: .bluesky, count: 2100, limit: 2000),
        ])
    }

    func testAltTextAtLimitIsAllowed() {
        let alt = String(repeating: "a", count: 1500) // exactly Mastodon's limit
        let post = DraftPost(text: "x", attachments: [Attachment(imageData: Data([0x1]), altText: alt)])
        let issues = PostValidator.validate(thread: [post], targets: [.mastodon], limits: limits)
        XCTAssertTrue(issues.isEmpty)
    }

    func testMediaValidationErrorMessageNamesTargetAndCounts() {
        let error = MediaValidationError.tooManyImages(target: .bluesky, count: 5, limit: 4)
        XCTAssertEqual(error.errorDescription,
                       "Bluesky supports at most 4 images per post; 5 were attached.")
    }

    func testReportsPerPostAndPerTarget() {
        let long = String(repeating: "a", count: 600) // > both limits
        let thread = [DraftPost(text: "ok"), DraftPost(text: long)]
        let issues = PostValidator.validate(thread: thread,
                                            targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertEqual(issues.count, 2) // post 1 over both targets
        XCTAssertTrue(issues.allSatisfy { if case .tooLong(let i, _, _, _) = $0 { return i == 1 } else { return false } })
    }

    // MARK: - Mastodon countable text

    func testMastodonCountableTextReplacesURLAndRemoteMention() {
        XCTAssertEqual(PostValidator.mastodonCountableText("hi @alice@example.social"), "hi @alice")
        XCTAssertEqual(
            PostValidator.mastodonCountableText("see https://example.com/some/very/long/path?q=1."),
            "see " + String(repeating: "x", count: 23) + ".")
        // Emails and local mentions are not remote mentions.
        XCTAssertEqual(PostValidator.mastodonCountableText("mail bob@example.com or @carol"),
                       "mail bob@example.com or @carol")
    }

    func testLongURLCountsAs23AndPassesAtMastodonLimit() {
        // 50-char URL counts as 23: 476 + 1 + 23 = exactly 500 countable
        // (527 raw graphemes, which would fail without the transform).
        let url = "https://example.com/" + String(repeating: "p", count: 30)
        let text = String(repeating: "a", count: 476) + " " + url
        XCTAssertEqual(PostValidator.graphemeCount(text), 527)
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.mastodon], limits: limits)
        XCTAssertTrue(issues.isEmpty)
    }

    func testShortURLStillCountsAs23ForMastodon() {
        // 12-char URL inflates to 23: raw 490 fits under 500, countable 501 does not.
        let text = String(repeating: "a", count: 477) + " https://a.io"
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.mastodon], limits: limits)
        XCTAssertEqual(issues, [.tooLong(postIndex: 0, target: .mastodon, count: 501, limit: 500)])
    }

    func testRemoteMentionCountsLocalPartOnlyForMastodon() {
        // Raw 515 graphemes; @alice@example.social counts as @alice → exactly 500.
        let text = String(repeating: "a", count: 493) + " @alice@example.social"
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.mastodon], limits: limits)
        XCTAssertTrue(issues.isEmpty)
    }

    func testBlueskyCountsRawGraphemesIncludingFullURLs() {
        // 301 raw graphemes: over Bluesky's 300 even though the Mastodon countable
        // transform (250 + 1 + 23 = 274) is well under both limits.
        let url = "https://example.com/" + String(repeating: "p", count: 30)
        let text = String(repeating: "a", count: 250) + " " + url
        let issues = PostValidator.validate(thread: [DraftPost(text: text)],
                                            targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertEqual(issues, [.tooLong(postIndex: 0, target: .bluesky, count: 301, limit: 300)])
    }

    // MARK: - Image cap single path

    func testImageCapViolationComesFromTargetLimits() {
        XCTAssertNil(limits.imageCountViolation(count: 4, for: .bluesky))
        guard case .tooManyImages(let target, let count, let limit)? =
                limits.imageCountViolation(count: 5, for: .mastodon) else {
            return XCTFail("expected a violation for 5 images")
        }
        XCTAssertEqual(target, .mastodon)
        XCTAssertEqual(count, 5)
        XCTAssertEqual(limit, 4)
        XCTAssertThrowsError(try limits.checkImageCount(5, for: .bluesky))
        XCTAssertNoThrow(try limits.checkImageCount(4, for: .bluesky))
    }
}
