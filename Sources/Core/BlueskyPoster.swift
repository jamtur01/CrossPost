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

    func post(thread: [DraftPost]) async throws -> [PostedItem] {
        try await runThread(thread, using: self)
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
        return (ref: ref, item: PostedItem(url: Self.webURL(recordURI: ref.recordURI, handle: handle)))
    }

    /// Build a bsky.app web URL from the at:// record URI's record key.
    static func webURL(recordURI: String, handle: String) -> String? {
        guard let rkey = recordURI.split(separator: "/").last else { return nil }
        return "https://bsky.app/profile/\(handle)/post/\(rkey)"
    }
}
