import ATProtoKit
import Foundation

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

    func resumeRefs(from ref: NativeRef) -> (root: Ref, parent: Ref)? {
        Self.resumeRefs(from: ref)
    }

    /// Rebuild the StrongReferences to reply under a post: parent is that post, root is
    /// its stored thread root, so the next post threads under the same root.
    static func resumeRefs(from ref: NativeRef) -> (root: Ref, parent: Ref)? {
        guard case let .bluesky(uri, cid, rootURI, rootCID) = ref else { return nil }
        return (root: strongRef(rootURI, rootCID), parent: strongRef(uri, cid))
    }

    /// Build a StrongReference (the uri+cid pair the write APIs take) tersely.
    static func strongRef(_ uri: String, _ cid: String) -> Ref {
        .init(recordURI: uri, cidHash: cid)
    }

    /// The result of creating a post record. `root` is the thread it replied into; without
    /// one the post is its own root. Stored so a later post can resume under the same root.
    static func postedItem(_ ref: Ref, root: Ref?, handle: String) -> PostedItem {
        let rootRef = root ?? ref
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: rootRef.recordURI, rootCID: rootRef.recordCID)
        return PostedItem(url: BlueskyURL.post(recordURI: ref.recordURI, handle: handle), ref: nativeRef)
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
        return (ref: ref, item: Self.postedItem(ref, root: root, handle: handle))
    }

    /// Build the images embed for a Bluesky post from attachments: enforce the
    /// per-post cap through TargetLimits (the reply flow calls this directly,
    /// bypassing pre-flight thread validation), transcode each to a budget JPEG,
    /// and drop blank alt text. Returns nil when there are no attachments.
    static func imagesEmbed(from attachments: [Attachment],
                            limits: TargetLimits = TargetLimits()) throws -> ATProtoBluesky.EmbedIdentifier? {
        guard !attachments.isEmpty else { return nil }
        try limits.checkImageCount(attachments.count, for: .bluesky)
        let queries = try attachments.map { attachment in
            try ATProtoTools.ImageQuery(
                imageData: ImageProcessor.jpegUnderBudget(attachment.imageData),
                fileName: "\(attachment.id.uuidString).jpg",
                altText: attachment.altText.nilIfBlank,
                aspectRatio: nil
            )
        }
        return .images(images: queries)
    }
}
