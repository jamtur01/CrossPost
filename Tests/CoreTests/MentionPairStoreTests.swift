@testable import CrossPost
import XCTest

final class MentionPairStoreTests: XCTestCase {
    private var store: MentionPairStore!

    override func setUp() {
        store = MentionPairStore(url: URL.temporaryDirectory
            .appending(path: "pairs-\(UUID())/mention-pairs.json"))
    }

    func testMissingFileIsEmpty() {
        XCTAssertEqual(store.load(), [])
    }

    func testSaveRoundTripsAndReplacesEitherAccount() throws {
        try store.save(MentionPair(mastodonAcct: "a@x.y", blueskyHandle: "a.bsky.social"))
        try store.save(MentionPair(mastodonAcct: "b@x.y", blueskyHandle: "b.bsky.social"))
        try store.save(MentionPair(mastodonAcct: "A@x.y", blueskyHandle: "new.bsky.social"))
        XCTAssertEqual(store.load(), [
            MentionPair(mastodonAcct: "b@x.y", blueskyHandle: "b.bsky.social"),
            MentionPair(mastodonAcct: "A@x.y", blueskyHandle: "new.bsky.social")
        ])
    }

    func testMalformedFileReadsAsEmpty() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), [])
    }
}
