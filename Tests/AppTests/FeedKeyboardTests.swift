import XCTest
@testable import CrossPost

final class FeedKeyboardTests: XCTestCase {
    private let posts = ["a", "b", "c"].map { TestFactory.feedPost(id: $0) }

    func testEmptyFeedHasNoSelection() {
        XCTAssertNil(feedSelectionID(movingDown: true, from: nil, in: []))
        XCTAssertNil(feedSelectionID(movingDown: false, from: "a", in: []))
    }

    func testNoSelectionSelectsFirst() {
        XCTAssertEqual(feedSelectionID(movingDown: true, from: nil, in: posts), "a")
        XCTAssertEqual(feedSelectionID(movingDown: false, from: nil, in: posts), "a")
    }

    func testMovesDownAndUp() {
        XCTAssertEqual(feedSelectionID(movingDown: true, from: "a", in: posts), "b")
        XCTAssertEqual(feedSelectionID(movingDown: false, from: "c", in: posts), "b")
    }

    func testClampsAtEnds() {
        XCTAssertEqual(feedSelectionID(movingDown: false, from: "a", in: posts), "a")  // top
        XCTAssertEqual(feedSelectionID(movingDown: true, from: "c", in: posts), "c")   // bottom
    }

    func testUnknownSelectionFallsBackToFirst() {
        XCTAssertEqual(feedSelectionID(movingDown: true, from: "gone", in: posts), "a")
    }
}
