import Foundation
import TootSDK

/// Posts to Mastodon via TootSDK. Ref is the status id used for in-reply-to chaining.
public struct MastodonPoster: Poster, ThreadPublisher {
    public typealias Ref = String
    public let target: PostTarget = .mastodon

    private let client: TootClient
    private let visibility: Post.Visibility

    public init(client: TootClient, visibility: Post.Visibility = .public) {
        self.client = client
        self.visibility = visibility
    }

    public func post(thread: [DraftPost]) async throws -> [PostedItem] {
        try await runThread(thread, using: self)
    }

    public func publishOne(_ draft: DraftPost, root: String?, parent: String?) async throws -> (ref: String, item: PostedItem) {
        var mediaIds: [String] = []
        for attachment in draft.attachments {
            // Transcode to JPEG so the bytes match the declared MIME type — the
            // picker accepts PNG/HEIC/GIF/TIFF, which Mastodon would otherwise reject.
            let jpeg = try ImageProcessor.jpegUnderBudget(attachment.imageData)
            let params = UploadMediaAttachmentParams(
                file: jpeg,
                thumbnail: nil,
                description: attachment.altText.isEmpty ? nil : attachment.altText,
                focus: nil)
            let uploaded = try await client.uploadMedia(params, mimeType: "image/jpeg")
            mediaIds.append(uploaded.id)
        }

        var params = PostParams(post: draft.text, visibility: visibility)
        if !mediaIds.isEmpty { params.mediaIds = mediaIds }
        if let parent { params.inReplyToId = parent } // Mastodon threads by parent chain only

        let post = try await client.publishPost(params)
        return (ref: post.id, item: PostedItem(url: post.url))
    }
}
