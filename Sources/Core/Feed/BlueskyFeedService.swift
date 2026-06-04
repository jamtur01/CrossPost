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
            let output = try await kit.listNotifications(with: [.mention, .reply])
            // Notifications aren't hydrated (no embeds/counts), so fetch the full
            // post views and render them exactly like the home feed.
            var seen = Set<String>()
            let uris = output.notifications.map(\.uri).filter { seen.insert($0).inserted }
            let hydrated = try await hydratePosts(uris)
            return uris.compactMap { hydrated[$0].map { Self.feedPost(fromPostView: $0) } }
        }
    }

    /// Hydrate posts by AT-URI (getPosts accepts up to 25 at a time).
    private func hydratePosts(_ uris: [String]) async throws
        -> [String: AppBskyLexicon.Feed.PostViewDefinition] {
        var result: [String: AppBskyLexicon.Feed.PostViewDefinition] = [:]
        var index = 0
        while index < uris.count {
            let chunk = Array(uris[index..<min(index + 25, uris.count)])
            let output = try await kit.getPosts(chunk)
            for post in output.posts { result[post.uri] = post }
            index += 25
        }
        return result
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

    public func thread(of post: FeedPost) async throws -> PostThread {
        guard case .bluesky(let uri, _, _, _) = post.nativeRef else {
            return PostThread(ancestors: [], descendants: [])
        }
        let output = try await kit.getPostThread(from: uri)
        guard case .threadViewPost(let thread) = output.thread else {
            return PostThread(ancestors: [], descendants: [])
        }
        var ancestors: [FeedPost] = []
        var node = thread.parent
        while case .threadViewPost(let parent)? = node {
            ancestors.append(Self.feedPost(fromPostView: parent.post))
            node = parent.parent
        }
        ancestors.reverse()

        // Walk the full reply tree (depth-first, parents before their children).
        var descendants: [FeedPost] = []
        var stack: [AppBskyLexicon.Feed.ThreadViewPostDefinition] = Self.childThreads(of: thread).reversed()
        while let node = stack.popLast() {
            descendants.append(Self.feedPost(fromPostView: node.post))
            stack.append(contentsOf: Self.childThreads(of: node).reversed())
        }
        return PostThread(ancestors: ancestors, descendants: descendants)
    }

    /// The direct reply threads of a node, in order.
    static func childThreads(
        of node: AppBskyLexicon.Feed.ThreadViewPostDefinition
    ) -> [AppBskyLexicon.Feed.ThreadViewPostDefinition] {
        (node.replies ?? []).compactMap { reply in
            if case .threadViewPost(let child) = reply { return child }
            return nil
        }
    }

    static func linkCard(from external: AppBskyLexicon.Embed.ExternalDefinition.ViewExternal) -> LinkCard? {
        guard let url = URL(string: external.uri) else { return nil }
        return LinkCard(url: url, title: external.title, description: external.description,
                        imageURL: external.thumbnailImageURL, providerName: url.host ?? "")
    }

    static func quotedPost(fromRecordView view: AppBskyLexicon.Embed.RecordDefinition.View) -> QuotedPost? {
        guard case .viewRecord(let vr) = view.record else { return nil }
        let record = vr.value.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
        let rkey = vr.uri.split(separator: "/").last.map(String.init) ?? ""
        var imageURL: URL?
        for embed in vr.embeds ?? [] {
            if case .embedImagesView(let v) = embed, let first = v.images.first {
                imageURL = first.fullSizeImageURL
                break
            }
        }
        return QuotedPost(
            id: "bluesky:\(vr.uri)",
            authorName: vr.author.displayName?.isEmpty == false ? vr.author.displayName! : vr.author.actorHandle,
            authorHandle: "@\(vr.author.actorHandle)",
            avatarURL: vr.author.avatarImageURL,
            text: AttributedString(record?.text ?? ""),
            imageURL: imageURL,
            webURL: URL(string: "https://bsky.app/profile/\(vr.author.actorHandle)/post/\(rkey)"))
    }

    public func profile(id: String) async throws -> Profile {
        Self.profile(from: try await kit.getProfile(for: id))
    }

    public func myProfile() async throws -> Profile {
        Self.profile(from: try await kit.getProfile(for: handle))
    }

    public func authorPosts(id: String) async throws -> [FeedPost] {
        let output = try await kit.getAuthorFeed(by: id)
        return output.feed.compactMap { Self.feedPost(from: $0, handle: handle) }
    }

    static func profile(from p: AppBskyLexicon.Actor.ProfileViewDetailedDefinition) -> Profile {
        Profile(
            id: p.actorHandle,
            target: .bluesky,
            name: p.displayName?.isEmpty == false ? p.displayName! : p.actorHandle,
            handle: "@\(p.actorHandle)",
            avatarURL: p.avatarImageURL,
            bannerURL: p.bannerImageURL,
            bio: AttributedString(p.description ?? ""),
            followers: p.followerCount ?? 0,
            following: p.followCount ?? 0,
            posts: p.postCount ?? 0,
            webURL: URL(string: "https://bsky.app/profile/\(p.actorHandle)"))
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

    /// Map a bare post view (timeline item, reply parent, etc.) to a FeedPost.
    static func feedPost(
        fromPostView p: AppBskyLexicon.Feed.PostViewDefinition,
        replyRoot: (uri: String, cid: String)? = nil,
        isReply: Bool? = nil
    ) -> FeedPost {
        let record = p.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
        var images: [FeedImage] = []
        var card: LinkCard?
        var quoted: QuotedPost?
        if let embed = p.embed {
            switch embed {
            case .embedImagesView(let view):
                images = view.images.map { FeedImage(url: $0.fullSizeImageURL, altText: $0.altText) }
            case .embedExternalView(let view):
                card = linkCard(from: view.external)
            case .embedRecordView(let view):
                quoted = quotedPost(fromRecordView: view)
            case .embedRecordWithMediaView(let view):
                quoted = quotedPost(fromRecordView: view.record)
                switch view.media {
                case .embedImagesView(let v):
                    images = v.images.map { FeedImage(url: $0.fullSizeImageURL, altText: $0.altText) }
                case .embedExternalView(let v):
                    card = linkCard(from: v.external)
                default:
                    break
                }
            default:
                break
            }
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
            authorID: p.author.actorHandle,
            avatarURL: p.author.avatarImageURL,
            authorURL: URL(string: "https://bsky.app/profile/\(p.author.actorHandle)"),
            date: p.indexedAt,
            text: AttributedString(record?.text ?? ""),
            images: images,
            card: card,
            quoted: quoted,
            webURL: URL(string: "https://bsky.app/profile/\(p.author.actorHandle)/post/\(rkey)"),
            isLiked: p.viewer?.likeURI != nil,
            isReposted: p.viewer?.repostURI != nil,
            replyCount: p.replyCount ?? 0,
            repostCount: p.repostCount ?? 0,
            likeCount: p.likeCount ?? 0,
            likeRecordURI: p.viewer?.likeURI,
            repostRecordURI: p.viewer?.repostURI,
            isReply: isReply ?? (record?.reply != nil),
            nativeRef: .bluesky(uri: p.uri, cid: p.cid, rootURI: root.uri, rootCID: root.cid))
    }
}
