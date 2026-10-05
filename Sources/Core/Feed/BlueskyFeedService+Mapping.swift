import ATProtoKit
import Foundation

extension BlueskyFeedService {
    /// The post URI a notification refers to, if any: the mention/reply/quote
    /// itself, or the liked/reposted subject. Single source of truth used both to
    /// decide what to hydrate and which hydrated post to attach - keep them in sync.
    static func referencedURI(_ notification: AppBskyLexicon.Notification.Notification) -> String? {
        switch notification.reason {
        case .mention, .reply, .quote: notification.uri
        case .like, .likeViaRepost, .repost, .repostViaRepost: notification.reasonSubjectURI
        default: nil
        }
    }

    static func notification(from notification: AppBskyLexicon.Notification.Notification,
                             hydrated: [String: FeedPost]) -> FeedNotification {
        let kind: FeedNotification.Kind = switch notification.reason {
        case .mention: .mention
        case .reply: .reply
        case .like, .likeViaRepost: .like
        case .repost, .repostViaRepost: .repost
        case .follow: .follow
        case .quote: .quote
        default: .other
        }
        let post = referencedURI(notification).flatMap { hydrated[$0] }
        return FeedNotification(
            id: notification.uri, kind: kind,
            actorName: displayOrHandle(notification.author.displayName, notification.author.actorHandle),
            actorHandle: "@\(notification.author.actorHandle)", actorID: notification.author.actorDID,
            avatarURL: notification.author.avatarImageURL, post: post, date: notification.indexedAt
        )
    }

    /// The direct reply threads of a node, in order.
    static func childThreads(
        of node: AppBskyLexicon.Feed.ThreadViewPostDefinition
    ) -> [AppBskyLexicon.Feed.ThreadViewPostDefinition] {
        (node.replies ?? []).compactMap { reply in
            if case let .threadViewPost(child) = reply {
                return child
            }
            return nil
        }
    }

    static func videoMedia(from view: AppBskyLexicon.Embed.VideoDefinition.View) -> FeedImage? {
        guard let url = URL(string: view.playlistURI) else { return nil }
        return FeedImage(
            url: url,
            previewURL: view.thumbnailImageURL.flatMap(URL.init(string:)),
            altText: view.altText ?? "",
            kind: .video,
            aspectRatio: Self.aspect(view.aspectRatio)
        )
    }

    static func aspect(_ ratio: AppBskyLexicon.Embed.AspectRatioDefinition?) -> Double? {
        guard let ratio, ratio.height > 0 else { return nil }
        return Double(ratio.width) / Double(ratio.height)
    }

    static func imageMedia(
        from image: AppBskyLexicon.Embed.ImagesDefinition.ViewImage
    ) -> FeedImage {
        FeedImage(
            url: image.fullSizeImageURL,
            previewURL: image.thumbnailImageURL,
            altText: image.altText,
            aspectRatio: aspect(image.aspectRatio)
        )
    }

    /// Bluesky GIFs (Tenor/Giphy) arrive as external embeds; play them inline when
    /// the link is a direct `.gif`, otherwise they fall back to a link card.
    static func gifMedia(from external: AppBskyLexicon.Embed.ExternalDefinition.ViewExternal) -> FeedImage? {
        guard let url = URL(string: external.uri),
              url.path.lowercased().hasSuffix(".gif")
        else { return nil }
        return FeedImage(
            url: url,
            previewURL: external.thumbnailImageURL,
            altText: external.title,
            kind: .gif
        )
    }

    static func linkCard(from external: AppBskyLexicon.Embed.ExternalDefinition.ViewExternal) -> LinkCard? {
        guard let url = URL(string: external.uri) else { return nil }
        return LinkCard(url: url, title: external.title, description: external.description,
                        imageURL: external.thumbnailImageURL, providerName: url.host ?? "")
    }

    /// Render a post record's text with its richtext facets resolved to links:
    /// mentions → the author's profile, links → their full URL, tags → the tag page.
    static func attributedText(_ record: AppBskyLexicon.Feed.PostRecord?) -> AttributedString {
        guard let record else { return AttributedString("") }
        let spans = (record.facets ?? []).compactMap { facet -> RichTextLinks.Span? in
            guard let url = facetURL(facet.features) else { return nil }
            return RichTextLinks.Span(byteStart: facet.index.byteStart,
                                      byteEnd: facet.index.byteEnd, url: url)
        }
        return RichTextLinks.attributed(record.text, spans: spans)
    }

    private static func facetURL(_ features: [AppBskyLexicon.RichText.Facet.FeaturesUnion]) -> URL? {
        for feature in features {
            switch feature {
            case let .mention(mention): return URL(string: BlueskyURL.profile(mention.did))
            case let .link(link): return URL(string: link.uri)
            case let .tag(tag): return URL(string: BlueskyURL.hashtag(tag.tag))
            case .unknown: continue
            }
        }
        return nil
    }

    static func quotedPost(fromRecordView view: AppBskyLexicon.Embed.RecordDefinition.View) -> QuotedPost? {
        guard case let .viewRecord(recordView) = view.record else { return nil }
        let record = recordView.value.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
        var imageURL: URL?
        for embed in recordView.embeds ?? [] {
            if case let .embedImagesView(view) = embed, let first = view.images.first {
                imageURL = first.thumbnailImageURL
                break
            }
        }
        return QuotedPost(
            id: "bluesky:\(recordView.uri)",
            authorName: displayOrHandle(recordView.author.displayName, recordView.author.actorHandle),
            authorHandle: "@\(recordView.author.actorHandle)",
            avatarURL: recordView.author.avatarImageURL,
            text: Self.attributedText(record),
            imageURL: imageURL,
            webURL: BlueskyURL.post(recordURI: recordView.uri, handle: recordView.author.actorHandle)
                .flatMap(URL.init(string:))
        )
    }

    static func lastMessage(_ union: ChatBskyLexicon.Conversation.ConversationViewDefinition.LastMessageUnion?)
        -> (text: String?, date: Date?) {
        guard case let .messageView(message)? = union else { return (nil, nil) }
        return (message.text, message.sentAt)
    }

    static func relationship(from viewer: AppBskyLexicon.Actor.ViewerStateDefinition?) -> AccountRelationship {
        AccountRelationship(
            isFollowing: viewer?.followingURI != nil,
            isFollowedBy: viewer?.followedByURI != nil,
            isMuting: viewer?.isMuted ?? false,
            isBlocking: viewer?.blockingURI != nil,
            followRecordURI: viewer?.followingURI,
            blockRecordURI: viewer?.blockingURI
        )
    }

    static func profile(fromBasic profile: AppBskyLexicon.Actor.ProfileViewDefinition) -> Profile {
        Profile(id: profile.actorDID,
                name: displayOrHandle(profile.displayName, profile.actorHandle),
                handle: "@\(profile.actorHandle)", avatarURL: profile.avatarImageURL, bannerURL: nil,
                bio: AttributedString(profile.description ?? ""), followers: 0, following: 0, posts: 0,
                webURL: URL(string: BlueskyURL.profile(profile.actorHandle)))
    }

    static func profile(fromDetailed profile: AppBskyLexicon.Actor.ProfileViewDetailedDefinition) -> Profile {
        Profile(
            id: profile.actorDID, // the stable id; follow/block records require the DID, not the handle
            name: displayOrHandle(profile.displayName, profile.actorHandle),
            handle: "@\(profile.actorHandle)",
            avatarURL: profile.avatarImageURL,
            bannerURL: profile.bannerImageURL,
            bio: AttributedString(profile.description ?? ""),
            followers: profile.followerCount ?? 0,
            following: profile.followCount ?? 0,
            posts: profile.postCount ?? 0,
            webURL: URL(string: BlueskyURL.profile(profile.actorHandle))
        )
    }

    static func feedPost(
        from item: AppBskyLexicon.Feed.FeedViewPostDefinition
    ) -> FeedPost? {
        let replyRoot: (uri: String, cid: String)? = if case let .postView(rootPost)? = item.reply?.root {
            (rootPost.uri, rootPost.cid)
        } else {
            nil
        }
        // A repost carries the original post plus who reposted it. Attribute the
        // booster and key the id by the reposter so the same post reposted by
        // several people (or also present as an original) stays distinct — else
        // ForEach ids collide and FeedMerge drops reposts.
        var boostedBy: String?
        var boostKey: String?
        if case let .reasonRepost(repost)? = item.reason {
            boostedBy = displayOrHandle(repost.by.displayName, repost.by.actorHandle)
            boostKey = repost.by.actorDID
        }
        var replyToHandle: String?
        if case let .postView(parent)? = item.reply?.parent {
            replyToHandle = "@\(parent.author.actorHandle)"
        }
        return feedPost(fromPostView: item.post, replyRoot: replyRoot, isReply: item.reply != nil,
                        replyToHandle: replyToHandle, boostedBy: boostedBy, boostKey: boostKey)
    }

    /// Map a bare post view (timeline item, reply parent, etc.) to a FeedPost.
    static func feedPost(
        fromPostView post: AppBskyLexicon.Feed.PostViewDefinition,
        replyRoot: (uri: String, cid: String)? = nil,
        isReply: Bool? = nil,
        replyToHandle: String? = nil,
        boostedBy: String? = nil,
        boostKey: String? = nil
    ) -> FeedPost {
        let record = post.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
        let content = embeddedContent(post.embed)
        // If no explicit replyRoot was supplied, derive it from the post's own record.
        let resolvedReplyRoot = replyRoot
            ?? record?.reply.map { ($0.root.recordURI, $0.root.recordCID) }
        let root = BlueskyThreadRef.root(postURI: post.uri, postCID: post.cid, replyRoot: resolvedReplyRoot)
        return FeedPost(
            id: boostKey.map { "bluesky:\($0):\(post.uri)" } ?? "bluesky:\(post.uri)",
            target: .bluesky,
            authorName: displayOrHandle(post.author.displayName, post.author.actorHandle),
            authorHandle: "@\(post.author.actorHandle)",
            authorID: post.author.actorDID, // stable id; post + author-feed lookups accept the DID
            avatarURL: post.author.avatarImageURL,
            date: post.indexedAt,
            text: Self.attributedText(record),
            images: content.images,
            card: content.card,
            quoted: content.quoted,
            webURL: BlueskyURL.post(recordURI: post.uri, handle: post.author.actorHandle)
                .flatMap(URL.init(string:)),
            isLiked: post.viewer?.likeURI != nil,
            isReposted: post.viewer?.repostURI != nil,
            isBookmarked: post.viewer?.isBookmarked ?? false,
            isPinned: post.viewer?.isPinned ?? false,
            replyCount: post.replyCount ?? 0,
            repostCount: post.repostCount ?? 0,
            likeCount: post.likeCount ?? 0,
            likeRecordURI: post.viewer?.likeURI,
            repostRecordURI: post.viewer?.repostURI,
            boostedBy: boostedBy,
            isReply: isReply ?? (record?.reply != nil),
            replyToHandle: replyToHandle,
            nativeRef: .bluesky(uri: post.uri, cid: post.cid, rootURI: root.uri, rootCID: root.cid)
        )
    }

    private struct PostContent {
        var images: [FeedImage] = []
        var card: LinkCard?
        var quoted: QuotedPost?
    }

    private static func embeddedContent(
        _ embed: AppBskyLexicon.Feed.PostViewDefinition.EmbedUnion?
    ) -> PostContent {
        guard let embed else { return PostContent() }
        switch embed {
        case let .embedImagesView(view):
            return PostContent(images: view.images.map(Self.imageMedia(from:)))
        case let .embedVideoView(view):
            return PostContent(images: videoMedia(from: view).map { [$0] } ?? [])
        case let .embedExternalView(view):
            if let gif = gifMedia(from: view.external) {
                return PostContent(images: [gif])
            }
            return PostContent(card: linkCard(from: view.external))
        case let .embedRecordView(view):
            return PostContent(quoted: quotedPost(fromRecordView: view))
        case let .embedRecordWithMediaView(view):
            let media = embeddedContent(mediaEmbed(view.media))
            return PostContent(images: media.images, card: media.card, quoted: quotedPost(fromRecordView: view.record))
        case .unknown:
            return PostContent()
        }
    }

    private static func mediaEmbed(
        _ media: AppBskyLexicon.Embed.RecordWithMediaDefinition.View.MediaUnion
    ) -> AppBskyLexicon.Feed.PostViewDefinition.EmbedUnion? {
        switch media {
        case let .embedImagesView(view): .embedImagesView(view)
        case let .embedVideoView(view): .embedVideoView(view)
        case let .embedExternalView(view): .embedExternalView(view)
        case .unknown: nil
        }
    }
}
