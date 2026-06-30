import Foundation
import ATProtoKit

/// Posts to Bluesky via ATProtoKit. Ref is the StrongReference used for reply root/parent.
struct BlueskyPoster: Poster, ThreadPublisher {
    typealias Ref = ComAtprotoLexicon.Repository.StrongReference
    let target: PostTarget = .bluesky

    private let bluesky: ATProtoBluesky
    private let handle: String

    init(bluesky: ATProtoBluesky, handle: String) {
        self.bluesky = bluesky
        self.handle = handle
    }

    func post(thread: [DraftPost], continuingFrom ref: NativeRef?) async throws -> [PostedItem] {
        try await runThread(thread, using: self, continuingFrom: ref)
    }

    /// Rebuild the StrongReferences to resume a thread: parent is the landed post,
    /// root is its stored thread root, so the next post threads under the same root.
    func resumeRefs(from ref: NativeRef) -> (root: Ref, parent: Ref)? {
        guard case .bluesky(let uri, let cid, let rootURI, let rootCID) = ref else { return nil }
        return (root: .init(recordURI: rootURI, cidHash: rootCID),
                parent: .init(recordURI: uri, cidHash: cid))
    }

    func publishOne(
        _ draft: DraftPost,
        root: Ref?,
        parent: Ref?
    ) async throws -> (ref: Ref, item: PostedItem) {
        var replyRef: AppBskyLexicon.Feed.PostRecord.ReplyReference?
        if let root, let parent {
            replyRef = .init(root: root, parent: parent)
        }

        var embed: ATProtoBluesky.EmbedIdentifier?
        if !draft.attachments.isEmpty {
            guard draft.attachments.count <= TargetLimits.imageMax else {
                throw MediaValidationError.tooManyImages(target: .bluesky,
                                                         count: draft.attachments.count,
                                                         limit: TargetLimits.imageMax)
            }
            let images = try draft.attachments.map { attachment in
                let jpeg = try ImageProcessor.jpegUnderBudget(attachment.imageData)
                return ATProtoTools.ImageQuery(
                    imageData: jpeg,
                    fileName: "\(attachment.id.uuidString).jpg",
                    altText: attachment.altText.isEmpty ? nil : attachment.altText,
                    aspectRatio: nil)
            }
            embed = .images(images: Array(images))
        }

        let ref = try await bluesky.createPostRecord(text: draft.text, replyTo: replyRef, embed: embed)
        // The thread root is the existing root (replies) or this post itself (top-level),
        // captured so a later post can resume the thread under the same root.
        let rootRef = root ?? ref
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: rootRef.recordURI, rootCID: rootRef.recordCID)
        return (ref: ref, item: PostedItem(url: Self.webURL(recordURI: ref.recordURI, handle: handle),
                                           ref: nativeRef))
    }

    /// Build a bsky.app web URL from the at:// record URI's record key.
    static func webURL(recordURI: String, handle: String) -> String? {
        guard let rkey = recordURI.split(separator: "/").last else { return nil }
        return "https://bsky.app/profile/\(handle)/post/\(rkey)"
    }
}
