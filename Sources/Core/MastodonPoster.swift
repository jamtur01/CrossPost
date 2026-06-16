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

    func post(thread: [DraftPost]) async throws -> [PostedItem] {
        try await runThread(thread, using: self)
    }

    func publishOne(_ draft: DraftPost, root: String?, parent: String?) async throws -> (ref: String, item: PostedItem) {
        guard draft.attachments.count <= TargetLimits.imageMax else {
            throw MediaValidationError.tooManyImages(target: .mastodon,
                                                     count: draft.attachments.count,
                                                     limit: TargetLimits.imageMax)
        }
        let maxBytes = draft.attachments.isEmpty ? 0 : await imageLimit.get(client)
        let mediaIds = try await client.uploadJPEGImages(draft.attachments, maxBytes: maxBytes)

        var params = PostParams(post: draft.text, visibility: draft.visibility.tootVisibility)
        if !mediaIds.isEmpty { params.mediaIds = mediaIds }
        if let parent { params.inReplyToId = parent } // Mastodon threads by parent chain only

        let post = try await client.publishPost(params)
        return (ref: post.id, item: PostedItem(url: post.url))
    }
}

extension PostVisibility {
    /// Maps onto TootSDK's visibility type; the raw strings are identical.
    var tootVisibility: Post.Visibility { Post.Visibility(rawValue: rawValue) ?? .public }
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
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let jpeg = try ImageProcessor.jpegUnderBudget(image.imageData, maxBytes: maxBytes)
                    let params = UploadMediaAttachmentParams(
                        file: jpeg,
                        thumbnail: nil,
                        description: image.altText.isEmpty ? nil : image.altText,
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
/// thread fetches instance info once instead of per post. Posting is sequential,
/// so the unsynchronised access is safe.
private final class ImageByteLimitCache: @unchecked Sendable {
    private var value: Int?
    func get(_ client: TootClient) async -> Int {
        if let value { return value }
        let limit = await client.mastodonImageByteLimit()
        value = limit
        return limit
    }
}
