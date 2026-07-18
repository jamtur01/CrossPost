import XCTest
@testable import CrossPost

final class BlueskyURLTests: XCTestCase {
    func testRkeyFromFullRecordURI() {
        XCTAssertEqual(
            BlueskyURL.rkey(from: "at://did:plc:abc123/app.bsky.feed.post/3kxyz"), "3kxyz")
    }

    func testRkeyRequiresAuthorityCollectionAndKey() {
        // A rootless URI's last "/"-separated component is the authority — treating
        // it as an rkey used to produce bogus post URLs.
        XCTAssertNil(BlueskyURL.rkey(from: "at://did:plc:abc123"))
        XCTAssertNil(BlueskyURL.rkey(from: "at://did:plc:abc123/app.bsky.feed.post"))
        XCTAssertNil(BlueskyURL.rkey(from: "at://"))
        XCTAssertNil(BlueskyURL.rkey(from: ""))
        XCTAssertNil(BlueskyURL.rkey(from: "https://bsky.app/profile/x/post/y"))
    }

    func testPostURLNilForRootlessURI() {
        XCTAssertNil(BlueskyURL.post(recordURI: "at://did:plc:abc123", handle: "user.bsky.social"))
    }

    func testPostURLFromFullRecordURI() {
        XCTAssertEqual(
            BlueskyURL.post(recordURI: "at://did:plc:abc123/app.bsky.feed.post/3kxyz",
                            handle: "user.bsky.social"),
            "https://bsky.app/profile/user.bsky.social/post/3kxyz")
    }
}
