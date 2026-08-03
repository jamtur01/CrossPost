import XCTest
@testable import CrossPost

final class ThreadReplyDisclosureTests: XCTestCase {
    func testLargeThreadInitiallyBoundsDescendantsAndPreservesContext() {
        var disclosure = ThreadReplyDisclosure()
        let ancestors = posts(prefix: "ancestor", count: 3)
        let focused = TestFactory.feedPost(id: "focused")
        let descendants = posts(
            prefix: "reply",
            count: ThreadReplyDisclosure.chunkSize + 7
        )

        let visible = disclosure.replace(
            ancestors: ancestors,
            focused: focused,
            descendants: descendants
        )

        XCTAssertEqual(ThreadReplyDisclosure.chunkSize, 25)
        XCTAssertEqual(
            visible.map(\.id),
            ancestors.map(\.id) + [focused.id] + descendants.prefix(25).map(\.id)
        )
        XCTAssertEqual(disclosure.remainingCount, 7)
    }

    func testRevealNextAppendsDeterministicChunksUntilEveryReplyIsVisible() {
        var disclosure = ThreadReplyDisclosure()
        let focused = TestFactory.feedPost(id: "focused")
        let total = ThreadReplyDisclosure.chunkSize * 2 + 3
        let descendants = posts(prefix: "reply", count: total)
        var visible = disclosure.replace(
            ancestors: [],
            focused: focused,
            descendants: descendants
        )

        visible.append(contentsOf: disclosure.revealNext())
        XCTAssertEqual(
            visible.map(\.id),
            [focused.id] + descendants.prefix(ThreadReplyDisclosure.chunkSize * 2).map(\.id)
        )
        XCTAssertEqual(disclosure.remainingCount, 3)

        visible.append(contentsOf: disclosure.revealNext())
        XCTAssertEqual(visible.map(\.id), [focused.id] + descendants.map(\.id))
        XCTAssertEqual(disclosure.remainingCount, 0)
        XCTAssertTrue(disclosure.revealNext().isEmpty)
    }

    func testSmallThreadRendersFullyAndFiltersDuplicateFocusedPost() {
        var disclosure = ThreadReplyDisclosure()
        let ancestor = TestFactory.feedPost(id: "ancestor")
        let focused = TestFactory.feedPost(id: "focused")
        let replies = posts(prefix: "reply", count: 2)

        let visible = disclosure.replace(
            ancestors: [ancestor, focused],
            focused: focused,
            descendants: [focused] + replies
        )

        XCTAssertEqual(visible.map(\.id), [ancestor.id, focused.id] + replies.map(\.id))
        XCTAssertEqual(disclosure.remainingCount, 0)
    }

    func testReplacementResetsDisclosureToTheInitialChunk() {
        var disclosure = ThreadReplyDisclosure()
        let focused = TestFactory.feedPost(id: "focused")
        let firstReplies = posts(
            prefix: "first",
            count: ThreadReplyDisclosure.chunkSize * 2
        )
        _ = disclosure.replace(ancestors: [], focused: focused, descendants: firstReplies)
        _ = disclosure.revealNext()

        let replacementReplies = posts(
            prefix: "replacement",
            count: ThreadReplyDisclosure.chunkSize + 4
        )
        let visible = disclosure.replace(
            ancestors: [],
            focused: focused,
            descendants: replacementReplies
        )

        XCTAssertEqual(
            visible.map(\.id),
            [focused.id] + replacementReplies.prefix(ThreadReplyDisclosure.chunkSize).map(\.id)
        )
        XCTAssertEqual(disclosure.remainingCount, 4)
    }

    func testResetClearsUndisclosedReplies() {
        var disclosure = ThreadReplyDisclosure()
        let focused = TestFactory.feedPost(id: "focused")
        let replies = posts(
            prefix: "reply",
            count: ThreadReplyDisclosure.chunkSize + 1
        )
        _ = disclosure.replace(ancestors: [], focused: focused, descendants: replies)

        disclosure.reset()

        XCTAssertEqual(disclosure.remainingCount, 0)
        XCTAssertTrue(disclosure.revealNext().isEmpty)
    }

    private func posts(prefix: String, count: Int) -> [FeedPost] {
        (0..<count).map { TestFactory.feedPost(id: "\(prefix)-\($0)") }
    }
}
