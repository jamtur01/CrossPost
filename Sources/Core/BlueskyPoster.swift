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

        let embed = try Self.imagesEmbed(from: draft.attachments)

        let ref = try await bluesky.createPostRecord(text: draft.text, replyTo: replyRef, embed: embed)
        // The thread root is the existing root (replies) or this post itself (top-level),
        // captured so a later post can resume the thread under the same root.
        let rootRef = root ?? ref
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: rootRef.recordURI, rootCID: rootRef.recordCID)
        return (ref: ref, item: PostedItem(url: BlueskyURL.post(recordURI: ref.recordURI, handle: handle),
                                           ref: nativeRef))
    }

    /// Build the images embed for a Bluesky post from attachments: enforce the
    /// per-post cap, transcode each to a budget JPEG, and drop blank alt text.
    /// Returns nil when there are no attachments. Shared by posting and replies.
    static func imagesEmbed(from attachments: [Attachment]) throws -> ATProtoBluesky.EmbedIdentifier? {
        guard !attachments.isEmpty else { return nil }
        guard attachments.count <= TargetLimits.imageMax else {
            throw MediaValidationError.tooManyImages(target: .bluesky,
                                                     count: attachments.count,
                                                     limit: TargetLimits.imageMax)
        }
        let queries = try attachments.map { attachment in
            ATProtoTools.ImageQuery(
                imageData: try ImageProcessor.jpegUnderBudget(attachment.imageData),
                fileName: "\(attachment.id.uuidString).jpg",
                altText: attachment.altText.nilIfBlank,
                aspectRatio: nil)
        }
        return .images(images: queries)
    }
}
