import Foundation
import ATProtoKit

struct BlueskyFeedService: FeedService {
    private let kit: ATProtoKit
    private let bluesky: ATProtoBluesky
    private let chat: ATProtoBlueskyChat
    private let handle: String
    private let didCache = OwnDIDCache()

    init(kit: ATProtoKit, bluesky: ATProtoBluesky, handle: String) {
        self.kit = kit
        self.bluesky = bluesky
        self.chat = ATProtoBlueskyChat(atProtoKitInstance: kit)
        self.handle = handle
    }

    /// The signed-in user's DID. Constant for the session, so it's fetched once and
    /// cached — the chat endpoints would otherwise pay a getProfile call each time.
    private func ownDID() async throws -> String {
        if let cached = await didCache.get() { return cached }
        let did = try await kit.getProfile(for: handle).actorDID
        await didCache.set(did)
        return did
    }

    /// Fetch up to ~`target` items by following the Bluesky cursor a few pages
    /// deep (the per-page max is 100).
    private func paged<T>(target: Int, maxPages: Int,
                          _ fetch: (String?) async throws -> (items: [T], cursor: String?)) async throws -> [T] {
        var collected: [T] = []
        var cursor: String?
        for _ in 0..<maxPages {
            let (items, next) = try await fetch(cursor)
            collected += items
            guard collected.count < target, !items.isEmpty, let next else { break }
            cursor = next
        }
        return collected
    }

    func loadFeed(_ kind: FeedKind) async throws -> [FeedPost] {
        switch kind {
        case .home:
            let feed = try await paged(target: 100, maxPages: 2) {
                let output = try await kit.getTimeline(limit: 100, cursor: $0)
                return (output.feed, output.cursor)
            }
            return feed.compactMap { Self.feedPost(from: $0) }
        case .notifications, .messages:
            return []   // these load through their own methods, not as posts
        }
    }

    func notifications() async throws -> [FeedNotification] {
        let notes = try await paged(target: 100, maxPages: 2) {
            let output = try await kit.listNotifications(limit: 100, cursor: $0)
            return (output.notifications, output.cursor)
        }
        // Hydrate the related posts: the mention/reply/quote itself, and the liked/
        // reposted subject. Fetching full post views gives us embeds and counts.
        var uris = Set<String>()
        for n in notes {
            switch n.reason {
            case .mention, .reply, .quote: uris.insert(n.uri)
            case .like, .likeViaRepost, .repost, .repostViaRepost:
                if let subject = n.reasonSubjectURI { uris.insert(subject) }
            default: break
            }
        }
        let hydrated = try await hydratePosts(Array(uris))
        return notes.map { n in
            let kind: FeedNotification.Kind
            switch n.reason {
            case .mention: kind = .mention
            case .reply: kind = .reply
            case .like, .likeViaRepost: kind = .like
            case .repost, .repostViaRepost: kind = .repost
            case .follow: kind = .follow
            case .quote: kind = .quote
            default: kind = .other
            }
            let postURI: String?
            switch kind {
            case .mention, .reply, .quote: postURI = n.uri
            case .like, .repost: postURI = n.reasonSubjectURI
            default: postURI = nil
            }
            let post = postURI.flatMap { hydrated[$0] }.map { Self.feedPost(fromPostView: $0) }
            return FeedNotification(
                id: n.uri, kind: kind,
                actorName: n.author.displayName?.isEmpty == false ? n.author.displayName! : n.author.actorHandle,
                actorHandle: "@\(n.author.actorHandle)", actorID: n.author.actorDID,
                avatarURL: n.author.avatarImageURL, post: post, date: n.indexedAt)
        }
    }

    func unreadNotificationCount() async throws -> Int {
        try await kit.getUnreadCount(priority: nil).count
    }

    func markNotificationsRead(upTo latest: FeedNotification?) async throws {
        // Bluesky marks read by timestamp; bound it to the newest notification we
        // actually loaded so one arriving mid-fetch isn't marked read while unseen.
        guard let latest else { return }
        try await kit.updateSeen(seenAt: latest.date)
    }

    /// Hydrate posts by AT-URI. getPosts accepts up to 25 at a time, so the
    /// chunks are fetched concurrently rather than one round-trip after another.
    private func hydratePosts(_ uris: [String]) async throws
        -> [String: AppBskyLexicon.Feed.PostViewDefinition] {
        let chunks = stride(from: 0, to: uris.count, by: 25).map {
            Array(uris[$0..<min($0 + 25, uris.count)])
        }
        var result: [String: AppBskyLexicon.Feed.PostViewDefinition] = [:]
        try await withThrowingTaskGroup(of: [AppBskyLexicon.Feed.PostViewDefinition].self) { group in
            for chunk in chunks {
                group.addTask { try await kit.getPosts(chunk).posts }
            }
            for try await posts in group {
                for post in posts { result[post.uri] = post }
            }
        }
        return result
    }

    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
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

    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
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

    func reply(to post: FeedPost, text: String, images: [Attachment],
               visibility _: PostVisibility) async throws -> PostedItem {
        guard case .bluesky(let uri, let cid, let rootURI, let rootCID) = post.nativeRef else {
            throw FeedError.wrongPlatform
        }
        let parent = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
        let root = ComAtprotoLexicon.Repository.StrongReference(recordURI: rootURI, cidHash: rootCID)
        let replyRef = AppBskyLexicon.Feed.PostRecord.ReplyReference(root: root, parent: parent)

        var embed: ATProtoBluesky.EmbedIdentifier?
        if !images.isEmpty {
            guard images.count <= TargetLimits.imageMax else {
                throw MediaValidationError.tooManyImages(target: .bluesky,
                                                         count: images.count,
                                                         limit: TargetLimits.imageMax)
            }
            let queries = try images.map { image in
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
        // The reply keeps the parent's thread root, so a continuation threads correctly.
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: rootURI, rootCID: rootCID)
        return PostedItem(url: "https://bsky.app/profile/\(handle)/post/\(rkey)", ref: nativeRef)
    }

    func quote(post: FeedPost, text: String, visibility _: PostVisibility) async throws -> PostedItem {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        let ref = try await bluesky.createPostRecord(
            text: text,
            embed: .record(strongReference: .init(recordURI: uri, cidHash: cid)))
        let rkey = ref.recordURI.split(separator: "/").last.map(String.init) ?? ""
        // A quote is a fresh top-level post, so it is its own thread root.
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: ref.recordURI, rootCID: ref.recordCID)
        return PostedItem(url: "https://bsky.app/profile/\(handle)/post/\(rkey)", ref: nativeRef)
    }

    func thread(of post: FeedPost) async throws -> PostThread {
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

    static func videoMedia(from view: AppBskyLexicon.Embed.VideoDefinition.View) -> FeedImage? {
        guard let url = URL(string: view.playlistURI) else { return nil }
        return FeedImage(url: url, altText: view.altText ?? "", kind: .video,
                         aspectRatio: Self.aspect(view.aspectRatio))
    }

    static func aspect(_ ratio: AppBskyLexicon.Embed.AspectRatioDefinition?) -> Double? {
        guard let ratio, ratio.height > 0 else { return nil }
        return Double(ratio.width) / Double(ratio.height)
    }

    /// Bluesky GIFs (Tenor/Giphy) arrive as external embeds; play them inline when
    /// the link is a direct `.gif`, otherwise they fall back to a link card.
    static func gifMedia(from external: AppBskyLexicon.Embed.ExternalDefinition.ViewExternal) -> FeedImage? {
        guard let url = URL(string: external.uri),
              url.absoluteString.split(separator: "?").first?.lowercased().hasSuffix(".gif") == true
        else { return nil }
        return FeedImage(url: url, altText: external.title, kind: .gif)
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
            case .mention(let mention): return URL(string: "https://bsky.app/profile/\(mention.did)")
            case .link(let link): return URL(string: link.uri)
            case .tag(let tag): return URL(string: "https://bsky.app/hashtag/\(tag.tag)")
            case .unknown: continue
            }
        }
        return nil
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
            text: Self.attributedText(record),
            imageURL: imageURL,
            webURL: URL(string: "https://bsky.app/profile/\(vr.author.actorHandle)/post/\(rkey)"))
    }

    func profile(id: String) async throws -> Profile {
        Self.profile(from: try await kit.getProfile(for: id))
    }

    func profile(forURL url: URL) async throws -> Profile? {
        guard let id = ProfileLink.blueskyID(from: url) else { return nil }
        return try await profile(id: id)
    }

    func deletePost(_ post: FeedPost) async throws {
        guard case .bluesky(let uri, _, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        try await bluesky.deleteRecord(.recordURI(atURI: uri))
    }

    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        if bookmarked {
            try await kit.createBookmark(uri: uri, cid: cid)
        } else {
            try await kit.deleteBookmark(uri: uri)
        }
        var copy = post
        copy.isBookmarked = bookmarked
        return copy
    }

    func setPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost {
        throw FeedError.notSupported("Pinning posts isn't supported on Bluesky yet.")
    }

    func editableSource(of post: FeedPost) async throws -> EditableSource {
        throw FeedError.notSupported("Bluesky posts can't be edited.")
    }

    func edit(post: FeedPost, text: String, spoiler: String) async throws -> FeedPost {
        throw FeedError.notSupported("Bluesky posts can't be edited.")
    }

    func likedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case .bluesky(let uri, _, _, _) = post.nativeRef else { return [] }
        let likes = try await paged(target: 200, maxPages: 3) {
            let output = try await kit.getLikes(from: uri, limit: 100, cursor: $0)
            return (output.likes, output.cursor)
        }
        return likes.map { Self.profile(fromBasic: $0.actor) }
    }

    func repostedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case .bluesky(let uri, _, _, _) = post.nativeRef else { return [] }
        let actors = try await paged(target: 200, maxPages: 3) {
            let output = try await kit.getRepostedBy(uri, limit: 100, cursor: $0)
            return (output.repostedBy, output.cursor)
        }
        return actors.map { Self.profile(fromBasic: $0) }
    }

    func conversations() async throws -> [Conversation] {
        let myDID = try await ownDID()
        let convos = try await paged(target: 200, maxPages: 3) {
            let output = try await chat.listConversations(limit: 100, cursor: $0)
            return (output.conversations, output.cursor)
        }
        return convos.compactMap { convo in
            // Fall back to the first member for a self-conversation (DM to yourself).
            guard let other = convo.members.first(where: { $0.actorDID != myDID }) ?? convo.members.first
            else { return nil }
            let last = Self.lastMessage(convo.lastMessage)
            return Conversation(
                id: convo.conversationID,
                otherName: other.displayName?.isEmpty == false ? other.displayName! : other.actorHandle,
                otherHandle: "@\(other.actorHandle)", otherID: other.actorDID,
                otherAvatarURL: other.avatarImageURL,
                lastMessage: last.text, lastDate: last.date, unreadCount: convo.unreadCount)
        }
    }

    func messages(in conversationID: String) async throws -> [DirectMessage] {
        let myDID = try await ownDID()
        // ATProtoKit's getMessages exposes no cursor, so fetch its max page (100).
        // Deep DM history beyond one page isn't reachable until the SDK adds a cursor.
        let output = try await chat.getMessages(from: conversationID, limit: 100)
        let messages = output.messages.compactMap { message -> DirectMessage? in
            guard case .messageView(let m) = message else { return nil }
            return DirectMessage(id: m.messageID, text: m.text, date: m.sentAt,
                                 isFromMe: m.sender.authorDID == myDID)
        }
        return messages.reversed()   // getMessages returns newest-first; show oldest-first
    }

    func sendMessage(_ text: String, to conversationID: String) async throws {
        _ = try await chat.sendMessage(
            to: conversationID,
            message: ChatBskyLexicon.Conversation.MessageInputDefinition(text: text))
    }

    // Bluesky has no per-user timeline stream (only the global firehose), so it polls.
    func liveUpdates() async -> AsyncStream<Void>? { nil }

    static func lastMessage(_ union: ChatBskyLexicon.Conversation.ConversationViewDefinition.LastMessageUnion?)
        -> (text: String?, date: Date?) {
        guard case .messageView(let m)? = union else { return (nil, nil) }
        return (m.text, m.sentAt)
    }

    func relationship(with id: String) async throws -> AccountRelationship {
        Self.relationship(from: try await kit.getProfile(for: id).viewer)
    }

    func relationships(with ids: [String]) async throws -> [String: AccountRelationship] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: AccountRelationship] = [:]
        // getProfiles silently caps its input at 25 actors, so page explicitly.
        for chunk in stride(from: 0, to: ids.count, by: 25).map({ Array(ids[$0..<min($0 + 25, ids.count)]) }) {
            for profile in try await kit.getProfiles(for: chunk).profiles {
                let relationship = Self.relationship(from: profile.viewer)
                // Callers may hold either form of id; key by whichever they asked with.
                result[profile.actorDID] = relationship
                result[profile.actorHandle] = relationship
            }
        }
        return result.filter { ids.contains($0.key) }
    }

    static func relationship(from viewer: AppBskyLexicon.Actor.ViewerStateDefinition?) -> AccountRelationship {
        AccountRelationship(
            isFollowing: viewer?.followingURI != nil,
            isFollowedBy: viewer?.followedByURI != nil,
            isMuting: viewer?.isMuted ?? false,
            isBlocking: viewer?.blockingURI != nil,
            followRecordURI: viewer?.followingURI,
            blockRecordURI: viewer?.blockingURI)
    }

    func setFollowing(_ following: Bool, for id: String,
                             current: AccountRelationship) async throws -> AccountRelationship {
        var rel = current
        if following {
            let ref = try await bluesky.createFollowRecord(actorDID: id)
            rel.isFollowing = true
            rel.followRecordURI = ref.recordURI
        } else if let uri = current.followRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: uri))
            rel.isFollowing = false
            rel.followRecordURI = nil
        }
        return rel
    }

    func setMuted(_ muted: Bool, for id: String,
                         current: AccountRelationship) async throws -> AccountRelationship {
        if muted { try await kit.muteActor(id) } else { try await kit.unmuteActor(id) }
        var rel = current
        rel.isMuting = muted
        return rel
    }

    func setBlocked(_ blocked: Bool, for id: String,
                           current: AccountRelationship) async throws -> AccountRelationship {
        var rel = current
        if blocked {
            let ref = try await bluesky.createBlockRecord(ofType: .actorBlock(actorDID: id))
            rel.isBlocking = true
            rel.blockRecordURI = ref.recordURI
        } else if let uri = current.blockRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: uri))
            rel.isBlocking = false
            rel.blockRecordURI = nil
        }
        return rel
    }

    func followers(of id: String) async throws -> [Profile] {
        let actors = try await paged(target: 200, maxPages: 3) {
            let output = try await kit.getFollowers(by: id, limit: 100, cursor: $0)
            return (output.followers, output.cursor)
        }
        return actors.map { Self.profile(fromBasic: $0) }
    }

    func following(of id: String) async throws -> [Profile] {
        let actors = try await paged(target: 200, maxPages: 3) {
            let output = try await kit.getFollows(from: id, limit: 100, cursor: $0)
            return (output.follows, output.cursor)
        }
        return actors.map { Self.profile(fromBasic: $0) }
    }

    static func profile(fromBasic p: AppBskyLexicon.Actor.ProfileViewDefinition) -> Profile {
        Profile(id: p.actorDID,
                name: p.displayName?.isEmpty == false ? p.displayName! : p.actorHandle,
                handle: "@\(p.actorHandle)", avatarURL: p.avatarImageURL, bannerURL: nil,
                bio: AttributedString(p.description ?? ""), followers: 0, following: 0, posts: 0,
                webURL: URL(string: "https://bsky.app/profile/\(p.actorHandle)"))
    }

    func myProfile() async throws -> Profile {
        Self.profile(from: try await kit.getProfile(for: handle))
    }

    func authorPosts(id: String) async throws -> [FeedPost] {
        let feed = try await paged(target: 100, maxPages: 2) {
            let output = try await kit.getAuthorFeed(by: id, limit: 100, cursor: $0)
            return (output.feed, output.cursor)
        }
        return feed.compactMap { Self.feedPost(from: $0) }
    }

    func pinnedPosts(of id: String) async throws -> [FeedPost] {
        []   // Bluesky pinning isn't supported in this app.
    }

    func search(_ query: String) async throws -> SearchResults {
        // Accounts and posts are independent endpoints, so query them concurrently.
        async let actors = kit.searchActors(matching: query, limit: 20)
        async let posts = kit.searchPosts(matching: query, limit: 20)
        return SearchResults(
            accounts: try await actors.actors.map(Self.profile(fromBasic:)),
            posts: try await posts.posts.map { Self.feedPost(fromPostView: $0) })
    }

    func bookmarkedPosts() async throws -> [FeedPost] {
        []   // Bluesky has no native bookmarks.
    }

    func likedPosts() async throws -> [FeedPost] {
        let did = try await ownDID()
        let feed = try await paged(target: 100, maxPages: 2) {
            let output = try await kit.getActorLikes(by: did, limit: 100, cursor: $0)
            return (output.feed, output.cursor)
        }
        return feed.compactMap { Self.feedPost(from: $0) }
    }

    func report(post: FeedPost, reason: ReportReason, comment: String) async throws {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        let subject = ComAtprotoLexicon.Moderation.CreateReportRequestBody.SubjectUnion
            .strongReference(.init(recordURI: uri, cidHash: cid))
        _ = try await kit.createReport(with: reason.blueskyReason,
                                       andContextof: comment.isEmpty ? nil : comment,
                                       subject: subject)
    }

    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        _ = try await kit.createReport(with: reason.blueskyReason,
                                       andContextof: comment.isEmpty ? nil : comment,
                                       subject: Self.accountReportSubject(did: id))
    }

    /// The report subject for an account. ATProtoKit's repoRef type exposes no
    /// public initializer across the module boundary, so it's built by decoding
    /// the lexicon's own JSON shape (the union keys off `$type`). Static and
    /// internal so the construction can be unit-tested without the network.
    static func accountReportSubject(
        did: String
    ) throws -> ComAtprotoLexicon.Moderation.CreateReportRequestBody.SubjectUnion {
        let json = Data(#"{"$type":"com.atproto.admin.defs#repoRef","did":"\#(did)"}"#.utf8)
        return try JSONDecoder().decode(
            ComAtprotoLexicon.Moderation.CreateReportRequestBody.SubjectUnion.self, from: json)
    }

    static func profile(from p: AppBskyLexicon.Actor.ProfileViewDetailedDefinition) -> Profile {
        Profile(
            id: p.actorDID,   // the stable id; follow/block records require the DID, not the handle
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
        from item: AppBskyLexicon.Feed.FeedViewPostDefinition
    ) -> FeedPost? {
        let replyRoot: (uri: String, cid: String)?
        if case .postView(let rootPost)? = item.reply?.root {
            replyRoot = (rootPost.uri, rootPost.cid)
        } else {
            replyRoot = nil
        }
        // A repost carries the original post plus who reposted it. Attribute the
        // booster and key the id by the reposter so the same post reposted by
        // several people (or also present as an original) stays distinct — else
        // ForEach ids collide and FeedMerge drops reposts.
        var boostedBy: String?
        var boostKey: String?
        if case .reasonRepost(let repost)? = item.reason {
            boostedBy = repost.by.displayName?.isEmpty == false
                ? repost.by.displayName! : repost.by.actorHandle
            boostKey = repost.by.actorDID
        }
        return feedPost(fromPostView: item.post, replyRoot: replyRoot, isReply: item.reply != nil,
                        boostedBy: boostedBy, boostKey: boostKey)
    }

    /// Map a bare post view (timeline item, reply parent, etc.) to a FeedPost.
    static func feedPost(
        fromPostView p: AppBskyLexicon.Feed.PostViewDefinition,
        replyRoot: (uri: String, cid: String)? = nil,
        isReply: Bool? = nil,
        boostedBy: String? = nil,
        boostKey: String? = nil
    ) -> FeedPost {
        let record = p.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
        var images: [FeedImage] = []
        var card: LinkCard?
        var quoted: QuotedPost?
        if let embed = p.embed {
            switch embed {
            case .embedImagesView(let view):
                images = view.images.map { FeedImage(url: $0.fullSizeImageURL, altText: $0.altText) }
            case .embedVideoView(let view):
                if let media = Self.videoMedia(from: view) { images = [media] }
            case .embedExternalView(let view):
                if let gif = Self.gifMedia(from: view.external) { images = [gif] }
                else { card = linkCard(from: view.external) }
            case .embedRecordView(let view):
                quoted = quotedPost(fromRecordView: view)
            case .embedRecordWithMediaView(let view):
                quoted = quotedPost(fromRecordView: view.record)
                switch view.media {
                case .embedImagesView(let v):
                    images = v.images.map { FeedImage(url: $0.fullSizeImageURL, altText: $0.altText) }
                case .embedVideoView(let v):
                    if let media = Self.videoMedia(from: v) { images = [media] }
                case .embedExternalView(let v):
                    if let gif = Self.gifMedia(from: v.external) { images = [gif] }
                    else { card = linkCard(from: v.external) }
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
            id: boostKey.map { "bluesky:\($0):\(p.uri)" } ?? "bluesky:\(p.uri)",
            target: .bluesky,
            authorName: p.author.displayName?.isEmpty == false
                ? p.author.displayName!
                : p.author.actorHandle,
            authorHandle: "@\(p.author.actorHandle)",
            authorID: p.author.actorDID,   // stable id; profile + author-feed lookups accept the DID
            avatarURL: p.author.avatarImageURL,
            date: p.indexedAt,
            text: Self.attributedText(record),
            images: images,
            card: card,
            quoted: quoted,
            webURL: URL(string: "https://bsky.app/profile/\(p.author.actorHandle)/post/\(rkey)"),
            isLiked: p.viewer?.likeURI != nil,
            isReposted: p.viewer?.repostURI != nil,
            isBookmarked: p.viewer?.isBookmarked ?? false,
            isPinned: p.viewer?.isPinned ?? false,
            replyCount: p.replyCount ?? 0,
            repostCount: p.repostCount ?? 0,
            likeCount: p.likeCount ?? 0,
            likeRecordURI: p.viewer?.likeURI,
            repostRecordURI: p.viewer?.repostURI,
            boostedBy: boostedBy,
            isReply: isReply ?? (record?.reply != nil),
            nativeRef: .bluesky(uri: p.uri, cid: p.cid, rootURI: root.uri, rootCID: root.cid))
    }
}

extension ReportReason {
    /// Closest matching Bluesky moderation reason.
    var blueskyReason: ComAtprotoLexicon.Moderation.ReasonTypeDefinition {
        switch self {
        case .spam: return .spam
        case .harassment: return .rude
        case .misleading: return .misleading
        case .sexual: return .sexual
        case .illegal: return .violation
        case .other: return .other
        }
    }
}

/// Session-scoped cache for the signed-in user's DID. A reference type so copies
/// of the (struct) service share one resolved value.
private actor OwnDIDCache {
    private var did: String?
    func get() -> String? { did }
    func set(_ value: String) { did = value }
}
