import Foundation
import ATProtoKit

public struct BlueskyFeedService: FeedService {
    public let target: PostTarget = .bluesky
    private let kit: ATProtoKit
    private let bluesky: ATProtoBluesky
    private let handle: String

    public init(kit: ATProtoKit, bluesky: ATProtoBluesky, handle: String) {
        self.kit = kit
        self.bluesky = bluesky
        self.handle = handle
    }

    public func loadFeed(_ kind: FeedKind) async throws -> [FeedPost] {
        switch kind {
        case .home:
            let output = try await kit.getTimeline()
            return output.feed.compactMap { Self.feedPost(from: $0, handle: handle) }
        case .mentions:
            let output = try await kit.listNotifications(
                with: [.mention, .reply])
            return output.notifications.compactMap { Self.feedPost(fromNotification: $0, handle: handle) }
        }
    }

    public func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { return post }
        var copy = post
        if liked {
            let ref = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
            let likeRef = try await bluesky.createLikeRecord(ref)
            copy.isLiked = true
            copy.likeRecordURI = likeRef.recordURI
        } else if let likeURI = post.likeRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: likeURI))
            copy.isLiked = false
            copy.likeRecordURI = nil
        }
        return copy
    }

    public func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { return post }
        var copy = post
        if reposted {
            let ref = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
            let repostRef = try await bluesky.createRepostRecord(ref)
            copy.isReposted = true
            copy.repostRecordURI = repostRef.recordURI
        } else if let repostURI = post.repostRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: repostURI))
            copy.isReposted = false
            copy.repostRecordURI = nil
        }
        return copy
    }

    public func reply(to post: FeedPost, text: String, images: [Attachment]) async throws -> PostedItem {
        guard case .bluesky(let uri, let cid, let rootURI, let rootCID) = post.nativeRef else {
            throw FeedError.wrongPlatform
        }
        let parent = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
        let root = ComAtprotoLexicon.Repository.StrongReference(recordURI: rootURI, cidHash: rootCID)
        let replyRef = AppBskyLexicon.Feed.PostRecord.ReplyReference(root: root, parent: parent)

        var embed: ATProtoBluesky.EmbedIdentifier?
        if !images.isEmpty {
            let queries = try images.prefix(4).map { image in
                let jpeg = try ImageProcessor.jpegUnderBudget(image.imageData)
                return ATProtoTools.ImageQuery(
                    imageData: jpeg,
                    fileName: "\(image.id.uuidString).jpg",
                    altText: image.altText.isEmpty ? nil : image.altText,
                    aspectRatio: nil)
            }
            embed = .images(images: Array(queries))
        }
        let ref = try await bluesky.createPostRecord(text: text, replyTo: replyRef, embed: embed)
        let rkey = ref.recordURI.split(separator: "/").last.map(String.init) ?? ""
        return PostedItem(url: "https://bsky.app/profile/\(handle)/post/\(rkey)")
    }

    public func parent(of post: FeedPost) async throws -> FeedPost? {
        guard post.isReply, case .bluesky(let uri, _, _, _) = post.nativeRef else { return nil }
        let output = try await kit.getPostThread(from: uri)
        guard case .threadViewPost(let thread) = output.thread,
              case .threadViewPost(let parent)? = thread.parent else { return nil }
        return Self.feedPost(fromPostView: parent.post)
    }

    static func feedPost(
        from item: AppBskyLexicon.Feed.FeedViewPostDefinition,
        handle: String
    ) -> FeedPost? {
        let replyRoot: (uri: String, cid: String)?
        if case .postView(let rootPost)? = item.reply?.root {
            replyRoot = (rootPost.uri, rootPost.cid)
        } else {
            replyRoot = nil
        }
        return feedPost(fromPostView: item.post, replyRoot: replyRoot, isReply: item.reply != nil)
    }

    static func feedPost(
        fromNotification n: AppBskyLexicon.Notification.Notification,
        handle: String
    ) -> FeedPost? {
        let record = n.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
        // Thread the reply to the real root from the notification's record, not the
        // notification post itself (which is the immediate parent).
        let replyRoot = record?.reply.map { ($0.root.recordURI, $0.root.recordCID) }
        let root = BlueskyThreadRef.root(postURI: n.uri, postCID: n.cid, replyRoot: replyRoot)
        let rkey = n.uri.split(separator: "/").last.map(String.init) ?? ""
        return FeedPost(
            id: "bluesky:\(n.uri)",
            target: .bluesky,
            authorName: n.author.displayName?.isEmpty == false
                ? n.author.displayName!
                : n.author.actorHandle,
            authorHandle: "@\(n.author.actorHandle)",
            avatarURL: n.author.avatarImageURL,
            date: n.indexedAt,
            text: AttributedString(record?.text ?? ""),
            images: [],
            webURL: URL(string: "https://bsky.app/profile/\(n.author.actorHandle)/post/\(rkey)"),
            isLiked: false,
            isReposted: false,
            isReply: record?.reply != nil,
            nativeRef: .bluesky(uri: n.uri, cid: n.cid, rootURI: root.uri, rootCID: root.cid))
    }

    /// Map a bare post view (timeline item, reply parent, etc.) to a FeedPost.
    static func feedPost(
        fromPostView p: AppBskyLexicon.Feed.PostViewDefinition,
        replyRoot: (uri: String, cid: String)? = nil,
        isReply: Bool? = nil
    ) -> FeedPost {
        let record = p.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
        var images: [FeedImage] = []
        if case .embedImagesView(let view)? = p.embed {
            images = view.images.map { FeedImage(url: $0.fullSizeImageURL, altText: $0.altText) }
        }
        // If no explicit replyRoot was supplied, derive it from the post's own record.
        let resolvedReplyRoot = replyRoot
            ?? record?.reply.map { ($0.root.recordURI, $0.root.recordCID) }
        let root = BlueskyThreadRef.root(postURI: p.uri, postCID: p.cid, replyRoot: resolvedReplyRoot)
        let rkey = p.uri.split(separator: "/").last.map(String.init) ?? ""
        return FeedPost(
            id: "bluesky:\(p.uri)",
            target: .bluesky,
            authorName: p.author.displayName?.isEmpty == false
                ? p.author.displayName!
                : p.author.actorHandle,
            authorHandle: "@\(p.author.actorHandle)",
            avatarURL: p.author.avatarImageURL,
            date: p.indexedAt,
            text: AttributedString(record?.text ?? ""),
            images: images,
            webURL: URL(string: "https://bsky.app/profile/\(p.author.actorHandle)/post/\(rkey)"),
            isLiked: p.viewer?.likeURI != nil,
            isReposted: p.viewer?.repostURI != nil,
            likeRecordURI: p.viewer?.likeURI,
            repostRecordURI: p.viewer?.repostURI,
            isReply: isReply ?? (record?.reply != nil),
            nativeRef: .bluesky(uri: p.uri, cid: p.cid, rootURI: root.uri, rootCID: root.cid))
    }
}
