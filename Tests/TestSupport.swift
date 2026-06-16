import Foundation
import AppKit
@testable import CrossPost

/// Builds a `FeedPost` with sensible defaults so tests only specify what they care about.
enum TestFactory {
    /// A small, genuinely decodable PNG, for attachment tests that need real image data.
    static func pngData(side: Int = 4) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
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
