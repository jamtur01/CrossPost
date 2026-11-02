import AppKit
@testable import CrossPost
import Foundation
import XCTest

/// Builds a `FeedPost` with sensible defaults so tests only specify what they care about.
enum TestFactory {
    /// A small, genuinely decodable PNG, for attachment tests that need real image data.
    static func pngData(side: Int = 4) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        return rep?.representation(using: .png, properties: [:]) ?? Data()
    }

    static func feedPost(
        target: PostTarget = .mastodon,
        id: String? = nil,
        authorName: String = "Author",
        authorHandle: String = "@author",
        authorID: String = "author-id",
        mentionHandles: [String] = [],
        visibility: String? = nil,
        spoilerText: String? = nil,
        isSensitive: Bool = false,
        text: AttributedString = AttributedString("hello"),
        date: Date = Date(timeIntervalSince1970: 0),
        webURL: URL? = nil,
        isLiked: Bool = false,
        isPinned: Bool = false,
        nativeRef: NativeRef? = nil
    ) -> FeedPost {
        let key = id ?? "\(target.rawValue):1"
        let nativeRef = nativeRef ?? (target == .mastodon
            ? .mastodon(statusID: key)
            : .bluesky(uri: "at://\(key)", cid: "cid", rootURI: "at://\(key)", rootCID: "cid"))
        return FeedPost(
            id: key,
            target: target,
            authorName: authorName,
            authorHandle: authorHandle,
            authorID: authorID,
            avatarURL: nil,
            date: date,
            text: text,
            images: [],
            webURL: webURL,
            isLiked: isLiked,
            isReposted: false,
            isPinned: isPinned,
            mentionHandles: mentionHandles,
            visibility: visibility,
            spoilerText: spoilerText,
            isSensitive: isSensitive,
            nativeRef: nativeRef
        )
    }

    /// Clears the instance URL, username, and handle `AccountStore` keeps in user
    /// defaults, so one test's accounts and self-handle don't leak into the next.
    @MainActor
    static func resetAccountDefaults() {
        let store = AccountStore()
        store.mastodonInstanceURL = ""
        store.mastodonUsername = ""
        store.blueskyHandle = ""
    }

    /// A timeline row for someone's boost of `post`: its own id, the same status.
    static func boost(of post: FeedPost, id: String, by booster: String = "Bob") -> FeedPost {
        FeedPost(id: id, target: post.target, authorName: post.authorName, authorHandle: post.authorHandle,
                 avatarURL: nil, date: post.date, text: post.text, images: [], webURL: nil,
                 isLiked: false, isReposted: false, boostedBy: booster,
                 spoilerText: post.spoilerText, isSensitive: post.isSensitive, nativeRef: post.nativeRef)
    }
}

/// A mutable value a test shares with `@Sendable` closures (notification
/// observers, fake service factories) that it reads back after awaiting them.
final class TestBox<Value>: @unchecked Sendable { // one test touches it at a time, never concurrently
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

extension XCTestCase {
    /// Polls `predicate` on the main actor every millisecond until it holds, failing
    /// the test if it still doesn't after `timeout` seconds.
    @MainActor
    func waitUntil(
        _ predicate: @MainActor () -> Bool,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() >= deadline {
                XCTFail("condition not met within timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
