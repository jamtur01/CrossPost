import XCTest
@testable import CrossPost

final class BlueskyPosterTests: XCTestCase {
    func testWebURLUsesRecordKeyAndHandle() {
        let url = BlueskyURL.post(
            recordURI: "at://did:plc:abc123/app.bsky.feed.post/3kqx7yz",
            handle: "alice.bsky.social")
        XCTAssertEqual(url, "https://bsky.app/profile/alice.bsky.social/post/3kqx7yz")
    }

    func testWebURLReturnsNilForEmptyURI() {
        XCTAssertNil(BlueskyURL.post(recordURI: "", handle: "alice.bsky.social"))
    }

    func testImagesEmbedIsNilWithoutAttachments() throws {
        XCTAssertNil(try BlueskyPoster.imagesEmbed(from: []))
    }

    func testImagesEmbedEnforcesCapThroughTargetLimits() {
        // The cap must throw before any decode work — the payloads aren't images.
        let attachments = (0..<5).map { _ in Attachment(imageData: Data([0x1])) }
        XCTAssertThrowsError(try BlueskyPoster.imagesEmbed(from: attachments)) { error in
            guard case MediaValidationError.tooManyImages(let target, let count, let limit) = error else {
                return XCTFail("expected tooManyImages, got \(error)")
            }
            XCTAssertEqual(target, .bluesky)
            XCTAssertEqual(count, 5)
            XCTAssertEqual(limit, 4)
        }
    }
}
