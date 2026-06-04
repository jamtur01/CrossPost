import Foundation
import ATProtoKit

/// Posts to Bluesky via ATProtoKit. Ref is the StrongReference used for reply root/parent.
public struct BlueskyPoster: Poster, ThreadPublisher {
    public typealias Ref = ComAtprotoLexicon.Repository.StrongReference
    public let target: PostTarget = .bluesky

    private let bluesky: ATProtoBluesky
    private let handle: String

    public init(bluesky: ATProtoBluesky, handle: String) {
        self.bluesky = bluesky
        self.handle = handle
    }

    public func post(thread: [DraftPost]) async throws -> [PostedItem] {
        try await runThread(thread, using: self)
    }

    public func publishOne(
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
        return (ref: ref, item: PostedItem(url: webURL(for: ref)))
    }

    /// Build a bsky.app web URL from the at:// record URI's record key.
    private func webURL(for ref: Ref) -> String? {
        guard let rkey = ref.recordURI.split(separator: "/").last else { return nil }
        return "https://bsky.app/profile/\(handle)/post/\(rkey)"
    }
}
