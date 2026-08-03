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
    /// The cache actor owns the in-flight fetch, so concurrent first callers share
    /// one getProfile round-trip instead of racing check-then-act.
    private func ownDID() async throws -> String {
        let kit = self.kit
        let handle = self.handle
        return try await didCache.did { try await kit.getProfile(for: handle).actorDID }
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
        // Hydrate the related posts (the mention/reply/quote itself, or the liked/
        // reposted subject) so notifications carry embeds and counts.
        let uris = Set(notes.compactMap(Self.referencedURI))
        let hydrated = try await hydratePosts(Array(uris))
        return notes.map { Self.notification(from: $0, hydrated: hydrated) }
    }

    /// The post URI a notification refers to, if any: the mention/reply/quote
    /// itself, or the liked/reposted subject. Single source of truth used both to
    /// decide what to hydrate and which hydrated post to attach - keep them in sync.
    static func referencedURI(_ n: AppBskyLexicon.Notification.Notification) -> String? {
        switch n.reason {
        case .mention, .reply, .quote: return n.uri
        case .like, .likeViaRepost, .repost, .repostViaRepost: return n.reasonSubjectURI
        default: return nil
        }
    }

    static func notification(from n: AppBskyLexicon.Notification.Notification,
                             hydrated: [String: AppBskyLexicon.Feed.PostViewDefinition]) -> FeedNotification {
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
        let post = referencedURI(n).flatMap { hydrated[$0] }.map { feedPost(fromPostView: $0) }
        return FeedNotification(
            id: n.uri, kind: kind,
            actorName: displayOrHandle(n.author.displayName, n.author.actorHandle),
            actorHandle: "@\(n.author.actorHandle)", actorID: n.author.actorDID,
            avatarURL: n.author.avatarImageURL, post: post, date: n.indexedAt)
    }

    func unreadNotificationCount() async throws -> Int {
        try await kit.getUnreadCount(priority: nil).count
    }

    func markNotificationsRead(upTo latest: FeedNotification?) async throws {
        // Mark everything seen as of now, matching the official Bluesky client, which
        // sends its sync time rather than a notification's timestamp. The server only
        // clears a notification when the stored seen time is strictly past it, and it
        // also counts notifications that listNotifications hides (muted, needs-review,
        // etc.) - so echoing the newest *shown* notification's timestamp can leave a
        // hidden or same-millisecond one counted forever. "Now" is strictly past every
        // notification the server has indexed. `latest` gates the call so an empty list
        // doesn't fire a pointless write.
        guard latest != nil else { return }
        try await kit.updateSeen(seenAt: Date())
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

    /// Build a StrongReference (the uri+cid pair the write APIs take) tersely.
    private static func strongRef(_ uri: String, _ cid: String)
        -> ComAtprotoLexicon.Repository.StrongReference {
        .init(recordURI: uri, cidHash: cid)
    }

    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        var copy = post
        if liked {
            // Already liked with a known record: creating a second like would
            // orphan the first server-side (only the newest URI would be kept
            // for undo), so a repeated like is a no-op.
            if let existing = post.likeRecordURI {
                copy.isLiked = true
                copy.likeRecordURI = existing
                return copy
            }
            let likeRef = try await bluesky.createLikeRecord(Self.strongRef(uri, cid))
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
            // Same idempotency guard as setLiked: never create a duplicate record.
            if let existing = post.repostRecordURI {
                copy.isReposted = true
                copy.repostRecordURI = existing
                return copy
            }
            let repostRef = try await bluesky.createRepostRecord(Self.strongRef(uri, cid))
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
        let parent = Self.strongRef(uri, cid)
        let root = Self.strongRef(rootURI, rootCID)
        let replyRef = AppBskyLexicon.Feed.PostRecord.ReplyReference(root: root, parent: parent)

        let embed = try BlueskyPoster.imagesEmbed(from: images)
        let ref = try await bluesky.createPostRecord(text: text, replyTo: replyRef, embed: embed)
        // The reply keeps the parent's thread root, so a continuation threads correctly.
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: rootURI, rootCID: rootCID)
        return PostedItem(url: BlueskyURL.post(recordURI: ref.recordURI, handle: handle), ref: nativeRef)
    }

    func quote(post: FeedPost, text: String, visibility _: PostVisibility) async throws -> PostedItem {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        let ref = try await bluesky.createPostRecord(
            text: text,
            embed: .record(strongReference: .init(recordURI: uri, cidHash: cid)))
        // A quote is a fresh top-level post, so it is its own thread root.
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: ref.recordURI, rootCID: ref.recordCID)
        return PostedItem(url: BlueskyURL.post(recordURI: ref.recordURI, handle: handle), ref: nativeRef)
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
            aspectRatio: Self.aspect(image.aspectRatio)
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
            case .mention(let mention): return URL(string: BlueskyURL.profile(mention.did))
            case .link(let link): return URL(string: link.uri)
            case .tag(let tag): return URL(string: BlueskyURL.hashtag(tag.tag))
            case .unknown: continue
            }
        }
        return nil
    }

    static func quotedPost(fromRecordView view: AppBskyLexicon.Embed.RecordDefinition.View) -> QuotedPost? {
        guard case .viewRecord(let vr) = view.record else { return nil }
        let record = vr.value.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
        var imageURL: URL?
        for embed in vr.embeds ?? [] {
            if case .embedImagesView(let v) = embed, let first = v.images.first {
                imageURL = first.thumbnailImageURL
                break
            }
        }
        return QuotedPost(
            id: "bluesky:\(vr.uri)",
            authorName: displayOrHandle(vr.author.displayName, vr.author.actorHandle),
            authorHandle: "@\(vr.author.actorHandle)",
            avatarURL: vr.author.avatarImageURL,
            text: Self.attributedText(record),
            imageURL: imageURL,
            webURL: BlueskyURL.post(recordURI: vr.uri, handle: vr.author.actorHandle)
                .flatMap(URL.init(string:)))
    }

    func profile(id: String) async throws -> Profile {
        Self.profile(fromDetailed: try await kit.getProfile(for: id))
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
                otherName: displayOrHandle(other.displayName, other.actorHandle),
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
        let requested = Set(ids)
        return result.filter { requested.contains($0.key) }
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
                name: displayOrHandle(p.displayName, p.actorHandle),
                handle: "@\(p.actorHandle)", avatarURL: p.avatarImageURL, bannerURL: nil,
                bio: AttributedString(p.description ?? ""), followers: 0, following: 0, posts: 0,
                webURL: URL(string: BlueskyURL.profile(p.actorHandle)))
    }

    func myProfile() async throws -> Profile {
        Self.profile(fromDetailed: try await kit.getProfile(for: handle))
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
                                       andContextof: comment.nilIfBlank,
                                       subject: subject)
    }

    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        _ = try await kit.createReport(with: reason.blueskyReason,
                                       andContextof: comment.nilIfBlank,
                                       subject: Self.accountReportSubject(did: id))
    }

    /// The report subject for an account. ATProtoKit's repoRef type exposes no
    /// public initializer across the module boundary, so it's built by encoding
    /// the lexicon's own JSON shape (the union keys off `$type`) and decoding it
    /// back — JSONEncoder handles escaping, so a hostile DID can't break the
    /// payload. Static and internal so it can be unit-tested without the network.
    static func accountReportSubject(
        did: String
    ) throws -> ComAtprotoLexicon.Moderation.CreateReportRequestBody.SubjectUnion {
        let json = try JSONEncoder().encode(RepoRefSubject(did: did))
        return try JSONDecoder().decode(
            ComAtprotoLexicon.Moderation.CreateReportRequestBody.SubjectUnion.self, from: json)
    }

    /// The lexicon wire shape of a `com.atproto.admin.defs#repoRef` subject.
    private struct RepoRefSubject: Encodable {
        let did: String

        private enum CodingKeys: String, CodingKey {
            case type = "$type"
            case did
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("com.atproto.admin.defs#repoRef", forKey: .type)
            try container.encode(did, forKey: .did)
        }
    }

    static func profile(fromDetailed p: AppBskyLexicon.Actor.ProfileViewDetailedDefinition) -> Profile {
        Profile(
            id: p.actorDID,   // the stable id; follow/block records require the DID, not the handle
            name: displayOrHandle(p.displayName, p.actorHandle),
            handle: "@\(p.actorHandle)",
            avatarURL: p.avatarImageURL,
            bannerURL: p.bannerImageURL,
            bio: AttributedString(p.description ?? ""),
            followers: p.followerCount ?? 0,
            following: p.followCount ?? 0,
            posts: p.postCount ?? 0,
            webURL: URL(string: BlueskyURL.profile(p.actorHandle)))
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
            boostedBy = displayOrHandle(repost.by.displayName, repost.by.actorHandle)
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
                images = view.images.map(Self.imageMedia(from:))
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
                    images = v.images.map(Self.imageMedia(from:))
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
        return FeedPost(
            id: boostKey.map { "bluesky:\($0):\(p.uri)" } ?? "bluesky:\(p.uri)",
            target: .bluesky,
            authorName: displayOrHandle(p.author.displayName, p.author.actorHandle),
            authorHandle: "@\(p.author.actorHandle)",
            authorID: p.author.actorDID,   // stable id; profile + author-feed lookups accept the DID
            avatarURL: p.author.avatarImageURL,
            date: p.indexedAt,
            text: Self.attributedText(record),
            images: images,
            card: card,
            quoted: quoted,
            webURL: BlueskyURL.post(recordURI: p.uri, handle: p.author.actorHandle).flatMap(URL.init(string:)),
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
/// of the (struct) service share one resolved value. The actor stores the fetch
/// Task itself, so every concurrent first caller awaits the same request and a
/// failure is retried by the next caller rather than cached forever.
private actor OwnDIDCache {
    private var inFlight: Task<String, Error>?

    func did(fetch: @escaping @Sendable () async throws -> String) async throws -> String {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await fetch() }
        inFlight = task
        do {
            return try await task.value
        } catch {
            inFlight = nil
            throw error
        }
    }
}
