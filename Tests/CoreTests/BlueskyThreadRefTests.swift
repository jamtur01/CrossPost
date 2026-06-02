import XCTest
@testable import CrossPost

final class BlueskyThreadRefTests: XCTestCase {
    func testTopLevelPostIsItsOwnRoot() {
        let root = BlueskyThreadRef.root(postURI: "at://p1", postCID: "c1", replyRoot: nil)
        XCTAssertEqual(root.uri, "at://p1")
        XCTAssertEqual(root.cid, "c1")
    }

    func testNestedPostUsesThreadRoot() {
        let root = BlueskyThreadRef.root(postURI: "at://p2", postCID: "c2",
                                         replyRoot: (uri: "at://root", cid: "croot"))
        XCTAssertEqual(root.uri, "at://root")
        XCTAssertEqual(root.cid, "croot")
    }
}
