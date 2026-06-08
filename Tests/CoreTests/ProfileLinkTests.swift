import XCTest
@testable import CrossPost

final class ProfileLinkTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testBlueskyProfileURLYieldsHandle() {
        XCTAssertEqual(ProfileLink.blueskyID(from: url("https://bsky.app/profile/alice.bsky.social")),
                       "alice.bsky.social")
    }

    func testBlueskyProfileURLYieldsDID() {
        XCTAssertEqual(ProfileLink.blueskyID(from: url("https://bsky.app/profile/did:plc:abc123")),
                       "did:plc:abc123")
    }

    func testBlueskyPostURLIsNotAProfile() {
        XCTAssertNil(ProfileLink.blueskyID(from: url("https://bsky.app/profile/alice.bsky.social/post/xyz")))
    }

    func testNonBlueskyHostIsNotABlueskyProfile() {
        XCTAssertNil(ProfileLink.blueskyID(from: url("https://example.com/profile/alice")))
    }

    func testMastodonProfileURLIsRecognised() {
        XCTAssertTrue(ProfileLink.isMastodonProfileURL(url("https://hachyderm.io/@mattray")))
    }

    func testMastodonStatusURLIsNotAProfile() {
        XCTAssertFalse(ProfileLink.isMastodonProfileURL(url("https://hachyderm.io/@mattray/123456")))
    }

    func testMastodonTagURLIsNotAProfile() {
        XCTAssertFalse(ProfileLink.isMastodonProfileURL(url("https://hachyderm.io/tags/swift")))
    }

    func testBareDomainIsNotAMastodonProfile() {
        XCTAssertFalse(ProfileLink.isMastodonProfileURL(url("https://hachyderm.io")))
    }

    func testRemoteMastodonProfileFormIsRecognised() {
        XCTAssertTrue(ProfileLink.isMastodonProfileURL(url("https://hachyderm.io/@user@other.social")))
    }

    func testLookalikeHandleWithDotIsRejected() {
        // Medium-style "/@first.last" isn't a Mastodon username (no dots allowed).
        XCTAssertFalse(ProfileLink.isMastodonProfileURL(url("https://medium.com/@first.last")))
    }

    func testLookalikeHandleWithHyphenIsRejected() {
        XCTAssertFalse(ProfileLink.isMastodonProfileURL(url("https://example.com/@some-blog")))
    }
}
