@testable import CrossPost
import XCTest

final class SentHistoryStoreTests: XCTestCase {
    private var store: SentHistoryStore!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        store = SentHistoryStore(url: URL.temporaryDirectory
            .appending(path: "history-\(UUID())/sent-history.json"))
    }

    func testMissingFileIsEmptyAndAnUnreadableOneIsNeverOverwritten() throws {
        XCTAssertEqual(try store.load(), [])
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let unreadable = Data("not json".utf8)
        try unreadable.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.record(sent("new", copies: [mastodon("1")])))
        XCTAssertEqual(try Data(contentsOf: store.url), unreadable)

        // Starting over keeps the old file, byte for byte, beside the new history.
        let kept = try store.setAside()
        XCTAssertEqual(try Data(contentsOf: kept), unreadable)
        XCTAssertEqual(kept.deletingLastPathComponent(), store.url.deletingLastPathComponent())
        try store.record(sent("new", copies: [mastodon("1")]))
        XCTAssertEqual(try store.load().map(\.text), ["new"])
    }

    func testRecordsNewestFirstAndRoundTripsBothNetworks() throws {
        let first = sent("first", copies: [mastodon("1"), bluesky("a")])
        let second = sent("second", copies: [mastodon("2"), bluesky("b")])
        try store.record(first)
        try store.record(second)
        XCTAssertEqual(try store.load(), [second, first])
    }

    func testKeepsOnlyTheNewestFiftySends() throws {
        for index in 0 ..< SentHistoryStore.limit + 5 {
            try store.record(sent("post \(index)", copies: [mastodon("\(index)")]))
        }
        let history = try store.load()
        XCTAssertEqual(history.count, SentHistoryStore.limit)
        XCTAssertEqual(history.first?.text, "post 54")
        XCTAssertEqual(history.last?.text, "post 5")
    }

    func testSingleNetworkSendRecordsOnlyThatNetwork() throws {
        try store.record(sent("only bluesky", copies: [bluesky("a")]))
        let saved = try XCTUnwrap(try store.load().first)
        XCTAssertNil(saved.copy(on: .mastodon))
        XCTAssertEqual(saved.copy(on: .bluesky)?.item.url, "https://bsky.app/a")
    }

    func testRetryThatLandsTheOtherNetworkUpdatesTheOriginalRecord() throws {
        let partial = SentPost(id: UUID(), date: start, text: "cross", postCount: 2,
                               copies: [mastodon("1", posts: 1)])
        try store.record(partial)
        try store.record(sent("unrelated", copies: [bluesky("z")]))
        XCTAssertEqual(partial.commonPublishedCount, 1, "a thread that stopped after one post shows one")
        let retryDate = start.addingTimeInterval(600)
        let retry = SentPost(id: UUID(), date: retryDate, text: "cross", postCount: 2,
                             copies: [mastodon("1", at: retryDate, posts: 2), bluesky("a", at: retryDate, posts: 2)])
        try store.record(retry)

        let history = try store.load()
        XCTAssertEqual(history.map(\.text), ["unrelated", "cross"])
        let merged = history[1]
        XCTAssertEqual(merged.id, partial.id)
        XCTAssertEqual(merged.date, start)
        XCTAssertEqual(merged.copy(on: .mastodon)?.date, start, "unchanged copy keeps its landing date")
        XCTAssertEqual(merged.copy(on: .mastodon)?.postCount, 2, "the retry's landed posts are counted")
        XCTAssertEqual(merged.copy(on: .bluesky)?.date, retryDate)
        XCTAssertEqual(merged.commonPublishedCount, 2)

        let uneven = SentPost(id: UUID(), date: start, text: "uneven", postCount: 4,
                              copies: [mastodon("7", posts: 4), bluesky("7", posts: 1)])
        XCTAssertNil(uneven.commonPublishedCount, "networks that landed different counts share none")
    }

    /// Mastodon status ids are per server, so the same id from another account is a
    /// different post, and only the signed-in accounts' copies are shown.
    func testCopiesBelongToTheAccountThatPublishedThem() throws {
        try store.record(sent("home", copies: [mastodon("1"), bluesky("a")]))
        try store.record(sent("elsewhere", copies: [mastodon("1", account: "other.example|me")]))
        let history = try store.load()
        XCTAssertEqual(history.map(\.text), ["elsewhere", "home"])

        let signedIn: [PostTarget: String] = [.mastodon: "other.example|me"]
        XCTAssertNil(history[1].limited(to: signedIn)?.copy(on: .bluesky))
        XCTAssertEqual(history.compactMap { $0.limited(to: signedIn) }.map(\.text), ["elsewhere"])

        // Bluesky copies match by the DID in the post's URI, so a handle change (the
        // copy was recorded under "me.bsky.social") keeps them, and another DID doesn't.
        XCTAssertNotNil(history[1].limited(to: [.bluesky: "did:plc:me"])?.copy(on: .bluesky))
        XCTAssertNil(history[1].limited(to: [.bluesky: "did:plc:someone-else"]))
        XCTAssertNil(history[1].limited(to: [.bluesky: ""]), "an unknown DID matches nothing")
    }

    private func sent(_ text: String, copies: [SentCopy]) -> SentPost {
        SentPost(id: UUID(), date: start, text: text, postCount: 1, copies: copies)
    }

    private func mastodon(_ id: String, at date: Date? = nil, posts: Int = 1,
                          account: String = "https://mastodon.example|me") -> SentCopy {
        SentCopy(target: .mastodon,
                 item: PostedItem(url: "https://mastodon.example/@me/\(id)", ref: .mastodon(statusID: id)),
                 date: date ?? start, account: account, postCount: posts)
    }

    private func bluesky(_ id: String, at date: Date? = nil, posts: Int = 1) -> SentCopy {
        let uri = "at://did:plc:me/app.bsky.feed.post/\(id)"
        return SentCopy(target: .bluesky,
                        item: PostedItem(url: "https://bsky.app/\(id)",
                                         ref: .bluesky(uri: uri, cid: "cid-\(id)", rootURI: uri, rootCID: "cid-\(id)")),
                        date: date ?? start, account: "me.bsky.social", postCount: posts)
    }
}

final class SentCopyStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMatchesByNativeRefIgnoringThreadContext() {
        let uri = "at://did:plc:me/app.bsky.feed.post/a"
        let copy = SentCopy(target: .bluesky,
                            item: PostedItem(url: nil, ref: .bluesky(uri: uri, cid: "c", rootURI: uri, rootCID: "c")),
                            date: now.addingTimeInterval(-3600), account: "me", postCount: 1)
        let listed = post(.bluesky(uri: uri, cid: "c2", rootURI: "", rootCID: ""), at: now.addingTimeInterval(-3600))
        let other = post(.bluesky(uri: "at://other", cid: "c", rootURI: uri, rootCID: "c"), at: now)

        XCTAssertEqual(SentCopyStatus.of(copy, in: [other, listed], now: now), .found(listed))
    }

    func testMissingCopyIsDeletedWhenNewerThanTheOldestFetchedPost() {
        let copy = mastodonCopy(sent: now.addingTimeInterval(-3600))
        let recent = [post(.mastodon(statusID: "9"), at: now.addingTimeInterval(-7200))]
        XCTAssertEqual(SentCopyStatus.of(copy, in: recent, now: now), .deleted)
    }

    func testMissingCopyOlderThanEveryFetchedPostIsTooOld() {
        let copy = mastodonCopy(sent: now.addingTimeInterval(-86400))
        let recent = [
            post(.mastodon(statusID: "8"), at: now.addingTimeInterval(-3600)),
            post(.mastodon(statusID: "7"), at: now.addingTimeInterval(-90000), pinned: true)
        ]
        XCTAssertEqual(SentCopyStatus.of(copy, in: recent, now: now), .olderThanRecent,
                       "an old pinned post must not widen the window")
    }

    func testJustSentCopyIsNotYetVisibleAndAnEmptyAccountMeansDeleted() {
        XCTAssertEqual(SentCopyStatus.of(mastodonCopy(sent: now.addingTimeInterval(-5)), in: [], now: now),
                       .notYetVisible)
        XCTAssertEqual(SentCopyStatus.of(mastodonCopy(sent: now.addingTimeInterval(-3600)), in: [], now: now),
                       .deleted)
    }

    private func mastodonCopy(sent date: Date) -> SentCopy {
        SentCopy(target: .mastodon, item: PostedItem(url: nil, ref: .mastodon(statusID: "1")), date: date,
                 account: "me", postCount: 1)
    }

    private func post(_ ref: NativeRef, at date: Date, pinned: Bool = false) -> FeedPost {
        let target: PostTarget = if case .mastodon = ref {
            .mastodon
        } else {
            .bluesky
        }
        return TestFactory.feedPost(target: target, id: "\(target.rawValue):\(ref.postKey)", authorName: "Me",
                                    authorHandle: "@me", authorID: "", date: date, isPinned: pinned, nativeRef: ref)
    }
}
