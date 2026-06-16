import Foundation
@testable import CrossPost

/// Builds a `FeedPost` with sensible defaults so tests only specify what they care about.
enum TestFactory {
    static func feedPost(
        target: PostTarget = .mastodon,
        id: String? = nil,
        authorName: String = "Author",
        authorHandle: String = "@author",
        authorID: String = "author-id",
        mentionHandles: [String] = [],
        visibility: String? = nil,
        text: AttributedString = AttributedString("hello")
    ) -> FeedPost {
        let key = id ?? "\(target.rawValue):1"
        let nativeRef: NativeRef = target == .mastodon
            ? .mastodon(statusID: key)
            : .bluesky(uri: "at://\(key)", cid: "cid", rootURI: "at://\(key)", rootCID: "cid")
        return FeedPost(
            id: key,
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
            visibility: visibility,
            nativeRef: nativeRef)
    }
}
