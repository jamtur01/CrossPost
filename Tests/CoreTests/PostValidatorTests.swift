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

    func testReportsPerPostAndPerTarget() {
        let long = String(repeating: "a", count: 600) // > both limits
        let thread = [DraftPost(text: "ok"), DraftPost(text: long)]
        let issues = PostValidator.validate(thread: thread,
                                            targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertEqual(issues.count, 2) // post 1 over both targets
        XCTAssertTrue(issues.allSatisfy { if case .tooLong(let i, _, _, _) = $0 { return i == 1 } else { return false } })
    }
}
