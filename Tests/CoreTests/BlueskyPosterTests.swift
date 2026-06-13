import XCTest
@testable import CrossPost

final class BlueskyPosterTests: XCTestCase {
    func testWebURLUsesRecordKeyAndHandle() {
        let url = BlueskyPoster.webURL(
            recordURI: "at://did:plc:abc123/app.bsky.feed.post/3kqx7yz",
            handle: "alice.bsky.social")
        XCTAssertEqual(url, "https://bsky.app/profile/alice.bsky.social/post/3kqx7yz")
    }

    func testWebURLReturnsNilForEmptyURI() {
        XCTAssertNil(BlueskyPoster.webURL(recordURI: "", handle: "alice.bsky.social"))
    }
}
