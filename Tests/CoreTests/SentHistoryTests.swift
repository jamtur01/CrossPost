@testable import CrossPost
import XCTest

final class SentHistoryStoreTests: XCTestCase {
    private var store: SentHistoryStore!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        store = SentHistoryStore(url: URL.temporaryDirectory
            .appending(path: "history-\(UUID())/sent-history.json"))
    }

    func testMissingAndMalformedFilesReadAsEmpty() throws {
        XCTAssertEqual(store.load(), [])
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), [])
    }

    func testRecordsNewestFirstAndRoundTripsBothNetworks() throws {
        let first = sent("first", copies: [mastodon("1"), bluesky("a")])
        let second = sent("second", copies: [mastodon("2"), bluesky("b")])
        try store.record(first)
        try store.record(second)
        XCTAssertEqual(store.load(), [second, first])
    }

    func testKeepsOnlyTheNewestFiftySends() throws {
        for index in 0 ..< SentHistoryStore.limit + 5 {
            try store.record(sent("post \(index)", copies: [mastodon("\(index)")]))
        }
        let history = store.load()
        XCTAssertEqual(history.count, SentHistoryStore.limit)
        XCTAssertEqual(history.first?.text, "post 54")
        XCTAssertEqual(history.last?.text, "post 5")
    }

    func testSingleNetworkSendRecordsOnlyThatNetwork() throws {
        try store.record(sent("only bluesky", copies: [bluesky("a")]))
        let saved = try XCTUnwrap(store.load().first)
        XCTAssertNil(saved.copy(on: .mastodon))
        XCTAssertEqual(saved.copy(on: .bluesky)?.item.url, "https://bsky.app/a")
    }

    func testRetryThatLandsTheOtherNetworkUpdatesTheOriginalRecord() throws {
        let partial = sent("cross", copies: [mastodon("1")])
        try store.record(partial)
        try store.record(sent("unrelated", copies: [bluesky("z")]))
        let retryDate = start.addingTimeInterval(600)
        let retry = SentPost(id: UUID(), date: retryDate, text: "cross", postCount: 2,
                             copies: [mastodon("1", at: retryDate), bluesky("a", at: retryDate)])
        try store.record(retry)

        let history = store.load()
        XCTAssertEqual(history.map(\.text), ["unrelated", "cross"])
        let merged = history[1]
        XCTAssertEqual(merged.id, partial.id)
        XCTAssertEqual(merged.date, start)
        XCTAssertEqual(merged.postCount, 2)
        XCTAssertEqual(merged.copy(on: .mastodon)?.date, start, "unchanged copy keeps its landing date")
        XCTAssertEqual(merged.copy(on: .bluesky)?.date, retryDate)
    }

    private func sent(_ text: String, copies: [SentCopy]) -> SentPost {
        SentPost(id: UUID(), date: start, text: text, postCount: 1, copies: copies)
    }

    private func mastodon(_ id: String, at date: Date? = nil) -> SentCopy {
        SentCopy(target: .mastodon,
                 item: PostedItem(url: "https://mastodon.example/@me/\(id)", ref: .mastodon(statusID: id)),
                 date: date ?? start)
    }

    private func bluesky(_ id: String, at date: Date? = nil) -> SentCopy {
        let uri = "at://did:plc:me/app.bsky.feed.post/\(id)"
        return SentCopy(target: .bluesky,
                        item: PostedItem(url: "https://bsky.app/\(id)",
                                         ref: .bluesky(uri: uri, cid: "cid-\(id)", rootURI: uri, rootCID: "cid-\(id)")),
                        date: date ?? start)
    }
}

final class SentCopyStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMatchesByNativeRefIgnoringThreadContext() {
        let uri = "at://did:plc:me/app.bsky.feed.post/a"
        let copy = SentCopy(target: .bluesky,
                            item: PostedItem(url: nil, ref: .bluesky(uri: uri, cid: "c", rootURI: uri, rootCID: "c")),
                            date: now.addingTimeInterval(-3600))
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
        SentCopy(target: .mastodon, item: PostedItem(url: nil, ref: .mastodon(statusID: "1")), date: date)
    }

    private func post(_ ref: NativeRef, at date: Date, pinned: Bool = false) -> FeedPost {
        let target: PostTarget = if case .mastodon = ref {
            .mastodon
        } else {
            .bluesky
        }
        return FeedPost(id: "\(target.rawValue):\(ref.postKey)", target: target, authorName: "Me",
                        authorHandle: "@me", avatarURL: nil, date: date, text: "hello", images: [],
                        webURL: nil, isLiked: false, isReposted: false, isPinned: pinned, nativeRef: ref)
    }
}
