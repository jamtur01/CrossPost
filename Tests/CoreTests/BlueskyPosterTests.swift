@testable import CrossPost
import XCTest

final class BlueskyPosterTests: XCTestCase {
    func testWebURLUsesRecordKeyAndHandle() {
        let url = BlueskyURL.post(
            recordURI: "at://did:plc:abc123/app.bsky.feed.post/3kqx7yz",
            handle: "alice.bsky.social"
        )
        XCTAssertEqual(url, "https://bsky.app/profile/alice.bsky.social/post/3kqx7yz")
    }

    func testWebURLReturnsNilForEmptyURI() {
        XCTAssertNil(BlueskyURL.post(recordURI: "", handle: "alice.bsky.social"))
    }

    /// A later post threads from the stored ref, so a reply must keep its thread's root
    /// and a top-level post or quote must be its own.
    func testPostedItemKeepsTheThreadRootForResuming() throws {
        let uri = "at://did:plc:me/app.bsky.feed.post/3new"
        let created = BlueskyPoster.strongRef(uri, "cid-new")
        let threadRoot = BlueskyPoster.strongRef("at://root", "cid-root")

        let reply = BlueskyPoster.postedItem(created, root: threadRoot, handle: "me.test")
        XCTAssertEqual(reply.ref, .bluesky(uri: uri, cid: "cid-new", rootURI: "at://root", rootCID: "cid-root"))
        XCTAssertEqual(reply.url, "https://bsky.app/profile/me.test/post/3new")

        let topLevel = BlueskyPoster.postedItem(created, root: nil, handle: "me.test")
        XCTAssertEqual(topLevel.ref, .bluesky(uri: uri, cid: "cid-new", rootURI: uri, rootCID: "cid-new"))

        let resumed = try XCTUnwrap(BlueskyPoster.resumeRefs(from: XCTUnwrap(reply.ref)))
        XCTAssertEqual(resumed.root.recordURI, "at://root")
        XCTAssertEqual(resumed.root.recordCID, "cid-root")
        XCTAssertEqual(resumed.parent.recordURI, uri)
        XCTAssertEqual(resumed.parent.recordCID, "cid-new")
        XCTAssertNil(BlueskyPoster.resumeRefs(from: .mastodon(statusID: "1")))
    }

    func testImagesEmbedIsNilWithoutAttachments() throws {
        XCTAssertNil(try BlueskyPoster.imagesEmbed(from: []))
    }

    func testImagesEmbedEnforcesCapThroughTargetLimits() {
        // The cap must throw before any decode work — the payloads aren't images.
        let attachments = (0 ..< 5).map { _ in Attachment(imageData: Data([0x1])) }
        XCTAssertThrowsError(try BlueskyPoster.imagesEmbed(from: attachments)) { error in
            guard case let MediaValidationError.tooManyImages(target, count, limit) = error else {
                return XCTFail("expected tooManyImages, got \(error)")
            }
            XCTAssertEqual(target, .bluesky)
            XCTAssertEqual(count, 5)
            XCTAssertEqual(limit, 4)
        }
    }
}
