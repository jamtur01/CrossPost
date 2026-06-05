import Foundation
@testable import CrossPost

/// Builds a `FeedPost` with sensible defaults so tests only specify what they care about.
enum TestFactory {
    static func feedPost(
        target: PostTarget = .mastodon,
        authorName: String = "Author",
        authorHandle: String = "@author",
        authorID: String = "author-id",
        mentionHandles: [String] = [],
        text: AttributedString = AttributedString("hello")
    ) -> FeedPost {
        let nativeRef: NativeRef = target == .mastodon
            ? .mastodon(statusID: "1")
            : .bluesky(uri: "at://1", cid: "cid", rootURI: "at://1", rootCID: "cid")
        return FeedPost(
            id: "\(target.rawValue):1",
            target: target,
            authorName: authorName,
            authorHandle: authorHandle,
            authorID: authorID,
            avatarURL: nil,
            date: Date(timeIntervalSince1970: 0),
            text: text,
            images: [],
            webURL: nil,
            isLiked: false,
            isReposted: false,
            mentionHandles: mentionHandles,
            nativeRef: nativeRef)
    }
}
