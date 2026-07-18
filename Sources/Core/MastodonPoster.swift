import Foundation
import TootSDK

/// Posts to Mastodon via TootSDK. Ref is the status id used for in-reply-to chaining.
struct MastodonPoster: Poster, ThreadPublisher {
    typealias Ref = String
    let target: PostTarget = .mastodon

    private let client: TootClient
    private let imageLimit = ImageByteLimitCache()

    init(client: TootClient) {
        self.client = client
    }

    func post(thread: [DraftPost], continuingFrom ref: NativeRef?) async throws -> [PostedItem] {
        try await runThread(thread, using: self, continuingFrom: ref)
    }

    /// Mastodon threads by parent chain only, so root and parent are both the status id.
    func resumeRefs(from ref: NativeRef) -> (root: String, parent: String)? {
        guard case .mastodon(let statusID) = ref else { return nil }
        return (root: statusID, parent: statusID)
    }

    func publishOne(_ draft: DraftPost, root: String?, parent: String?) async throws -> (ref: String, item: PostedItem) {
        let maxBytes = draft.attachments.isEmpty ? 0 : await imageLimit.get(client)
        let mediaIds = try await client.uploadJPEGImages(draft.attachments, maxBytes: maxBytes)

        var params = PostParams(post: draft.text, visibility: draft.visibility.tootVisibility)
        if !mediaIds.isEmpty { params.mediaIds = mediaIds }
        if let parent { params.inReplyToId = parent } // Mastodon threads by parent chain only

        let post = try await client.publishPost(params)
        return (ref: post.id, item: PostedItem(url: post.url, ref: .mastodon(statusID: post.id)))
    }
}

extension PostVisibility {
    /// Maps onto TootSDK's visibility type case by case. Exhaustive on purpose:
    /// a future visibility must fail to compile here rather than silently fall
    /// back to .public and widen the post's audience.
    var tootVisibility: Post.Visibility {
        switch self {
        case .public: return .public
        case .unlisted: return .unlisted
        case .private: return .private
        case .direct: return .direct
        }
    }
}

extension ReportReason {
    /// Closest matching Mastodon report category.
    var mastodonCategory: ReportCategory {
        switch self {
        case .spam: return .spam
        case .harassment: return .abusive
        case .misleading: return .other
        case .sexual: return .sensitive
        case .illegal: return .legal
        case .other: return .other
        }
    }
}

extension TootClient {
    /// The instance's maximum image upload size in bytes, falling back to Mastodon's
    /// documented 10 MB default when the instance doesn't report one.
    func mastodonImageByteLimit() async -> Int {
        let reported = try? await getInstanceInfoV2().configuration?.mediaAttachments?.imageSizeLimit
        return (reported ?? nil) ?? TargetLimits.mastodonImageBytes
    }

    /// Transcode and upload images concurrently — they're independent — returning
    /// media ids in attachment order so the post's gallery order is preserved.
    /// Transcoding to JPEG makes the bytes match the declared MIME type (the picker
    /// accepts PNG/HEIC/GIF/TIFF), scaling down only past the instance's image size
    /// limit so a large photo can't fail mid-thread.
    func uploadJPEGImages(_ images: [Attachment], maxBytes: Int) async throws -> [String] {
        // Encode sequentially: the pipeline is pure ImageIO/CoreGraphics and
        // thread-safe (the coordinator already runs both posters' encodes
        // concurrently), but parallelising the CPU-bound encodes within one post
        // would only multiply peak memory — each holds a full decoded bitmap.
        // The network uploads are what benefit from running concurrently.
        let encoded: [(jpeg: Data, altText: String)] = try images.map {
            (try ImageProcessor.jpegUnderBudget($0.imageData, maxBytes: maxBytes), $0.altText)
        }
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, item) in encoded.enumerated() {
                group.addTask {
                    let params = UploadMediaAttachmentParams(
                        file: item.jpeg,
                        thumbnail: nil,
                        description: item.altText.nilIfBlank,
                        focus: nil)
                    return (index, try await self.uploadMedia(params, mimeType: "image/jpeg").id)
                }
            }
            var indexed: [(Int, String)] = []
            for try await entry in group { indexed.append(entry) }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

/// Caches the instance image-size limit for the duration of one cross-post so a
/// thread fetches instance info once instead of per post. An actor because the
/// poster can be driven from concurrent tasks; two racing first reads at worst
/// fetch the limit twice, which is harmless.
private actor ImageByteLimitCache {
    private var value: Int?
    func get(_ client: TootClient) async -> Int {
        if let value { return value }
        let limit = await client.mastodonImageByteLimit()
        value = limit
        return limit
    }
}
