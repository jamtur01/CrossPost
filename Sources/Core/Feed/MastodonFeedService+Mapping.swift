import Foundation
import TootSDK

extension MastodonFeedService {
    static func notification(from notification: TootNotification) -> FeedNotification {
        let kind: FeedNotification.Kind = switch notification.type {
        case .mention: .mention
        case .favourite: .like
        case .repost: .repost
        case .follow, .followRequest: .follow
        case .poll: .poll
        case .quote, .quotedUpdate: .quote
        default: .other
        }
        return FeedNotification(
            id: notification.id, kind: kind,
            actorName: displayOrHandle(notification.account.displayName, notification.account.acct),
            actorHandle: "@\(notification.account.acct)", actorID: notification.account.id,
            avatarURL: URL(string: notification.account.avatar),
            emojis: emojiMap(notification.account.emojis),
            post: notification.post.map { Self.feedPost(from: $0) }, date: notification.createdAt
        )
    }

    /// Whether a server version string advertises quote-post support (4.4+),
    /// or nil when no leading `major.minor` semver can be parsed (forks report
    /// free-form versions; callers proceed best-effort for those).
    static func supportsQuotePosts(version: String) -> Bool? {
        let head = version.prefix { ("0" ... "9").contains($0) || $0 == "." }
        let parts = head.split(separator: ".")
        guard let first = parts.first, let major = Int(first) else { return nil }
        let minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return major > 4 || (major == 4 && minor >= 4)
    }

    static func relationship(from relationship: Relationship?) -> AccountRelationship {
        AccountRelationship(
            isFollowing: relationship?.following ?? false,
            isFollowedBy: relationship?.followedBy ?? false,
            isMuting: relationship?.muting ?? false,
            isBlocking: relationship?.blocking ?? false
        )
    }

    static func profile(from account: Account) -> Profile {
        Profile(
            id: account.id,
            name: displayOrHandle(account.displayName, account.acct),
            handle: "@\(account.acct)",
            avatarURL: URL(string: account.avatar),
            bannerURL: URL(string: account.header),
            bio: HTMLRenderer.renderAttributed(account.note),
            followers: account.followersCount,
            following: account.followingCount,
            posts: account.postsCount,
            webURL: URL(string: account.url),
            emojis: emojiMap(account.emojis)
        )
    }

    /// Shortcode → static image URL across Mastodon emoji lists; later lists win.
    static func emojiMap(_ lists: [Emoji]...) -> [String: URL] {
        var map: [String: URL] = [:]
        for list in lists {
            for emoji in list {
                if let url = URL(string: emoji.staticUrl) {
                    map[emoji.shortcode] = url
                }
            }
        }
        return map
    }

    /// Map a Mastodon attachment to feed media. Animated GIFs arrive as `gifv`
    /// (a looping MP4) and video as `video`; both play inline. Audio is skipped.
    static func media(from att: MediaAttachment) -> FeedImage? {
        guard let url = URL(string: att.url) else { return nil }
        let previewURL = att.previewUrl.flatMap(URL.init(string:))
        let type = att.type.value
        if type == .image {
            return FeedImage(url: url, previewURL: previewURL, altText: att.description ?? "")
        }
        if type == .gifv || type == .video {
            return FeedImage(
                url: url,
                previewURL: previewURL,
                altText: att.description ?? "",
                kind: .video,
                aspectRatio: att.aspectRatio
            )
        }
        return nil
    }

    static func linkCard(from card: Card?) -> LinkCard? {
        guard let card, let url = URL(string: card.url) else { return nil }
        let provider = card.providerName?.isEmpty == false ? card.providerName! : (url.host ?? "")
        return LinkCard(url: url, title: card.title, description: card.description,
                        imageURL: card.image.flatMap(URL.init(string:)), providerName: provider)
    }

    static func quotedPost(from quote: Quote?) -> QuotedPost? {
        guard let quote, case let .post(quotedStatus)? = quote.quotedPost else { return nil }
        // `quotedPost` is also non-nil when the quoted account is blocked/muted;
        // only render an explicitly accepted quote (or flavors that report no state).
        if let state = quote.state?.value, state != .accepted {
            return nil
        }
        let quoted = quotedStatus.displayPost
        let image = quoted.mediaAttachments.first { $0.type.value == .image }
        return QuotedPost(
            id: "mastodon:\(quoted.id)",
            authorName: displayOrHandle(quoted.account.displayName, quoted.account.acct),
            authorHandle: "@\(quoted.account.acct)",
            avatarURL: URL(string: quoted.account.avatar),
            text: HTMLRenderer.renderAttributed(quoted.content ?? ""),
            imageURL: image.flatMap {
                $0.previewUrl.flatMap(URL.init(string:)) ?? URL(string: $0.url)
            },
            webURL: quoted.url.flatMap(URL.init(string:)),
            emojis: emojiMap(quoted.account.emojis, quoted.emojis)
        )
    }

    static func feedPost(from post: Post) -> FeedPost {
        // A boost carries its real content in `displayPost` (the reblogged status);
        // render that, and attribute it to the booster.
        let display = post.displayPost
        let boostedBy = post.displayingRepost
            ? displayOrHandle(post.account.displayName, post.account.acct)
            : nil
        let images = display.mediaAttachments.compactMap { Self.media(from: $0) }
        return FeedPost(
            // Identify by the outer timeline entry, not `display.id`: the same status
            // boosted by several people must stay distinct (else ForEach IDs collide
            // and FeedMerge drops boosts). `nativeRef` still targets `display.id`.
            id: "mastodon:\(post.id)",
            target: .mastodon,
            authorName: displayOrHandle(display.account.displayName, display.account.acct),
            authorHandle: "@\(display.account.acct)",
            authorID: display.account.id,
            avatarURL: URL(string: display.account.avatar),
            date: display.createdAt,
            text: HTMLRenderer.renderAttributed(display.content ?? ""),
            images: images,
            card: linkCard(from: display.card),
            quoted: quotedPost(from: display.quote),
            webURL: display.url.flatMap(URL.init(string:)),
            isLiked: display.favourited ?? false,
            isReposted: display.reposted ?? false,
            isBookmarked: display.bookmarked ?? false,
            isPinned: display.pinned ?? false,
            replyCount: display.repliesCount,
            repostCount: display.repostsCount,
            likeCount: display.favouritesCount,
            boostedBy: boostedBy,
            mentionHandles: display.mentions.map { "@\($0.acct)" },
            visibility: display.visibility.rawValue,
            spoilerText: display.spoilerText.nilIfBlank,
            isSensitive: display.sensitive,
            isReply: display.inReplyToId != nil,
            replyToHandle: replyToHandle(of: display),
            emojis: emojiMap(post.account.emojis, display.account.emojis, display.emojis),
            nativeRef: .mastodon(statusID: display.id)
        )
    }

    /// The parent author's "@acct". Mastodon gives only the parent's account id, so
    /// it resolves when that is the author (a thread) or someone the post mentions.
    private static func replyToHandle(of post: Post) -> String? {
        guard let parentID = post.inReplyToAccountId else { return nil }
        if parentID == post.account.id {
            return "@\(post.account.acct)"
        }
        return post.mentions.first { $0.id == parentID }.map { "@\($0.acct)" }
    }
}
