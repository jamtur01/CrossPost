import XCTest
@testable import CrossPost

final class FeedMergeTests: XCTestCase {
    private func post(_ id: String, liked: Bool = false) -> FeedPost {
        FeedPost(id: id, target: .bluesky, authorName: "a", authorHandle: "@a", avatarURL: nil,
                 date: Date(timeIntervalSince1970: 0), text: AttributedString(""), images: [],
                 webURL: nil, isLiked: liked, isReposted: false, nativeRef: .mastodon(statusID: id))
    }

    func testEmptyExistingReturnsFetched() {
        let merged = FeedMerge.merge(existing: [], fetched: [post("1"), post("2")])
        XCTAssertEqual(merged.map(\.id), ["1", "2"])
    }

    func testNewPostsPrependInFetchedOrder() {
        let merged = FeedMerge.merge(existing: [post("2"), post("3")], fetched: [post("1"), post("2")])
        XCTAssertEqual(merged.map(\.id), ["1", "2", "3"]) // only "1" is new, prepended
    }

    func testFullOverlapIsUnchanged() {
        let merged = FeedMerge.merge(existing: [post("1"), post("2")], fetched: [post("1"), post("2")])
        XCTAssertEqual(merged.map(\.id), ["1", "2"])
    }

    func testExistingActionStateIsPreserved() {
        let merged = FeedMerge.merge(existing: [post("1", liked: true)], fetched: [post("1", liked: false)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isLiked) // existing optimistic state kept, not clobbered by fetched
    }
}
