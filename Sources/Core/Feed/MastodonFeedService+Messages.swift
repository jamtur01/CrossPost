import Foundation
import TootSDK

// MARK: Direct messages

/// Mastodon DMs are statuses with `direct` visibility; a conversation is the
/// thread they form among one set of participants (Mastodon starts a separate
/// conversation when a reply changes who is mentioned). Replying means posting
/// another direct status that mentions every participant and replies to the
/// newest one, so the service remembers those per conversation (Mastodon has no
/// "get conversation by id").
extension MastodonFeedService {
    func conversations(includeHistory: Bool,
                       onPage: @Sendable ([Conversation]) async -> Void) async throws -> [Conversation] {
        let threads = dmThreads
        let convos = try await paged(target: 80, maxPages: includeHistory ? 2 : 1, onPage: { convos in
            await threads.remember(convos)
            await onPage(convos.compactMap(Self.conversation(from:)))
        }, {
            try await client.getConversations($0, limit: 40).page
        })
        return convos.compactMap(Self.conversation(from:))
    }

    func messages(in conversationID: String) async throws -> [DirectMessage] {
        let state = try await dmThreads.thread(conversationID)
        guard let statusID = state.lastStatusID else { return [] }
        async let ownID = ownAccountID()
        let posts = try await wholeThread(around: statusID)
        let myID = try await ownID
        let direct = Self.conversationPosts(posts, participantIDs: Set(state.accountIDs), ownID: myID)
        if let newest = direct.last {
            await dmThreads.setLastStatus(newest.id, for: conversationID)
        }
        if state.mastodonID != nil, state.isUnread {
            await markRead(conversationID)
        }
        return direct.map { Self.directMessage(from: $0, ownID: myID) }
    }

    /// Every status in the thread containing `statusID`, fetched from its root so
    /// replies on sibling branches are included.
    private func wholeThread(around statusID: String) async throws -> [Post] {
        let context = try await client.getContext(id: statusID)
        if let root = context.ancestors.first {
            return try await [root] + client.getContext(id: root.id).descendants
        }
        return try await [client.getPost(id: statusID)] + context.descendants
    }

    func sendMessage(_ text: String, to conversationID: String) async throws {
        let thread = try await dmThreads.thread(conversationID)
        let extra = try await Self.extraRecipients(in: text, participants: thread.accts,
                                                   localDomain: localDomain.get(client))
        guard extra.isEmpty else { throw FeedError.extraRecipients(extra) }
        let mentions = thread.accts.map { "@\($0)" }.joined(separator: " ")
        var params = PostParams(post: "\(mentions) \(text)", visibility: .direct)
        params.inReplyToId = thread.lastStatusID
        let posted = try await client.publishPost(params)
        await dmThreads.setLastStatus(posted.id, for: conversationID)
    }

    /// `accountID` is a Mastodon account id, or an acct (`user@server`) from search.
    func conversation(with accountID: String) async throws -> Conversation {
        let account = accountID.contains("@")
            ? try await client.lookupAccount(uri: accountID.trimmingPrefix("@").description)
            : try await client.getAccount(by: accountID)
        let recent = try await client.getConversations(limit: 40).result
        await dmThreads.remember(recent)
        if let existing = recent.first(where: { $0.accounts.map(\.id) == [account.id] }),
           let convo = Self.conversation(from: existing) {
            return convo
        }
        let id = "new:\(account.id)"
        await dmThreads.start(id, account: account)
        return Conversation(id: id, otherName: displayOrHandle(account.displayName, account.acct),
                            otherHandle: "@\(account.acct)", otherID: account.id,
                            otherAvatarURL: URL(string: account.avatar),
                            lastMessage: nil, lastDate: nil, unreadCount: 0)
    }

    private func markRead(_ conversationID: String) async {
        do {
            _ = try await client.setConversationAsRead(id: conversationID)
            await dmThreads.markRead(conversationID)
        } catch {
            Log.feed.error("Couldn't mark Mastodon conversation \(conversationID) read: \(error)")
        }
    }

    private func ownAccountID() async throws -> String {
        try await dmThreads.ownID { try await client.verifyCredentials().id }
    }

    /// Group DMs are shown as one row named for everyone in them.
    static func conversation(from convo: TootSDK.Conversation) -> Conversation? {
        guard let first = convo.accounts.first else { return nil }
        let names = convo.accounts.map { displayOrHandle($0.displayName, $0.acct) }
        return Conversation(
            id: convo.id,
            otherName: names.joined(separator: ", "),
            otherHandle: convo.accounts.map { "@\($0.acct)" }.joined(separator: " "),
            otherID: first.id,
            otherAvatarURL: URL(string: first.avatar),
            lastMessage: convo.lastPost.map { messageText(from: $0) },
            lastDate: convo.lastPost?.createdAt,
            unreadCount: convo.unread ? 1 : 0
        )
    }

    static func directMessage(from post: Post, ownID: String) -> DirectMessage {
        DirectMessage(id: post.id, text: messageText(from: post), date: post.createdAt,
                      isFromMe: post.account.id == ownID)
    }

    /// Direct statuses whose audience (author and mentions, minus the viewer) is
    /// exactly the conversation's participants, oldest first. Mastodon lists the
    /// viewer as the participant of a conversation with themselves, so the viewer
    /// is dropped from both sides.
    static func conversationPosts(_ posts: [Post], participantIDs: Set<String>, ownID: String) -> [Post] {
        let participantIDs = participantIDs.subtracting([ownID])
        return posts.filter { post in
            guard post.visibility.value == .direct else { return false }
            var audience = Set(post.mentions.map(\.id))
            audience.insert(post.account.id)
            audience.remove(ownID)
            return audience == participantIDs
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// Accounts `text` @mentions beyond `participants`. Mastodon delivers a direct
    /// status to everyone it mentions, so each would silently become a recipient.
    /// Uses Mastodon's own mention pattern; local accts are qualified with
    /// `localDomain` so `@alice` and `@alice@home.example` compare equal.
    static func extraRecipients(in text: String, participants: [String],
                                localDomain: String?) throws -> [String] {
        func qualified(_ acct: String) -> String {
            let acct = acct.lowercased()
            guard !acct.contains("@"), let localDomain else { return acct }
            return "\(acct)@\(localDomain.lowercased())"
        }
        let known = Set(participants.map(qualified))
        let pattern = #"(?<![=/\w])@([a-z0-9_]+(?:[.-]+[a-z0-9_]+)*(?:@\w+(?:[.-]+\w+)*)?)"#
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(text.startIndex..., in: text)
        var extra: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let acctRange = Range(match.range(at: 1), in: text) else { continue }
            let acct = String(text[acctRange])
            if !known.contains(qualified(acct)), !extra.contains(acct) {
                extra.append(acct)
            }
        }
        return extra
    }

    /// A DM's text without the leading @mentions that address it.
    static func messageText(from post: Post) -> String {
        let text = String(HTMLRenderer.renderAttributed(post.content ?? "").characters)
        let body = text.replacingOccurrences(of: #"^(?:@[^\s@]+(?:@[^\s]+)?\s+)+"#, with: "",
                                             options: .regularExpression)
        return body.isEmpty ? text : body
    }
}

/// Per-conversation reply state, keyed by the id the app holds: Mastodon's
/// conversation id, or `new:<account id>` until the first message is sent.
actor MastodonDMThreads {
    struct Thread {
        var accts: [String]
        var accountIDs: [String]
        var lastStatusID: String?
        var isUnread = false
        var mastodonID: String?
    }

    private var threads: [String: Thread] = [:]
    private var cachedOwnID: String?

    func remember(_ convos: [TootSDK.Conversation]) {
        for convo in convos {
            threads[convo.id] = Thread(accts: convo.accounts.map(\.acct), accountIDs: convo.accounts.map(\.id),
                                       lastStatusID: convo.lastPost?.id, isUnread: convo.unread,
                                       mastodonID: convo.id)
        }
    }

    func start(_ id: String, account: Account) {
        if threads[id] == nil {
            threads[id] = Thread(accts: [account.acct], accountIDs: [account.id])
        }
    }

    func thread(_ id: String) throws -> Thread {
        guard let thread = threads[id] else {
            throw FeedError.notSupported("This conversation is no longer loaded. Reopen it from Messages.")
        }
        return thread
    }

    func setLastStatus(_ statusID: String, for id: String) {
        threads[id]?.lastStatusID = statusID
    }

    func markRead(_ id: String) {
        threads[id]?.isUnread = false
    }

    func ownID(fetch: @Sendable () async throws -> String) async throws -> String {
        if let cachedOwnID {
            return cachedOwnID
        }
        let id = try await fetch()
        cachedOwnID = id
        return id
    }
}
