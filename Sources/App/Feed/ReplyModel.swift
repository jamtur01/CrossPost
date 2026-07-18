import Foundation
import SwiftUI

@MainActor
@Observable
final class ReplyModel {
    let post: FeedPost
    var text: String = ""
    var attachments: [Attachment] = []
    /// Mastodon reply visibility, seeded from the parent so it never widens the
    /// audience by default. Unused for Bluesky.
    var visibility: PostVisibility
    var isSending = false
    var blockedIssues: [ValidationIssue]?
    var errorMessage: String?
    /// True once the reply has landed; the sheet's success state keys off this.
    private(set) var didPost = false
    /// Permalink of the posted reply when the platform returned one. Optional and
    /// URL-typed — no sentinel string stands in for "sent but no link".
    private(set) var postedURL: URL?

    private let store: AccountStore
    private let makeService: @MainActor (PostTarget, AccountStore) async throws -> FeedService

    init(post: FeedPost, store: AccountStore,
         makeService: @escaping @MainActor (PostTarget, AccountStore) async throws -> FeedService
             = FeedServiceFactory.make) {
        self.post = post
        self.store = store
        self.makeService = makeService
        self.text = Self.prefill(for: post, store: store)
        self.visibility = PostVisibility(mastodon: post.visibility) ?? .public
    }

    /// Mastodon needs the people a reply addresses named in the body to mention and
    /// notify them, so we seed the author plus anyone the parent mentioned
    /// (de-duplicated, excluding your own handle). Bluesky threads replies through
    /// the parent reference and notifies the author on its own, so it starts empty.
    private static func prefill(for post: FeedPost, store: AccountStore) -> String {
        guard post.target == .mastodon else { return "" }
        let ownHandle = store.mastodonUsername.isEmpty ? "" : "@\(store.mastodonUsername)"
        var seen: Set<String> = []
        var mentions: [String] = []
        for handle in [post.authorHandle] + post.mentionHandles {
            let trimmed = handle.trimmingCharacters(in: .whitespaces)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, key != ownHandle.lowercased(),
                  seen.insert(key).inserted else { continue }
            mentions.append(trimmed)
        }
        return mentions.isEmpty ? "" : mentions.joined(separator: " ") + " "
    }

    var limit: Int {
        post.target == .bluesky ? TargetLimits.blueskyMax : store.mastodonMaxChars
    }

    var count: Int { PostValidator.graphemeCount(text) }

    var canSend: Bool {
        !isSending && !DraftPost(text: text, attachments: attachments).isEmpty
    }

    /// Returns true only when the reply was actually posted, so the UI doesn't
    /// report success on a validation or network failure.
    @discardableResult
    func send() async -> Bool {
        // Authoritative guard: a second queued send (double tap / ⌘↩ race) returns
        // before posting again. The disabled button alone doesn't prevent the race.
        guard canSend else { return false }
        isSending = true
        blockedIssues = nil
        errorMessage = nil
        defer { isSending = false }
        let draft = DraftPost(text: text, attachments: attachments)
        let issues = PostValidator.validate(thread: [draft], targets: [post.target], limits: store.limits)
        guard issues.isEmpty else {
            blockedIssues = issues
            return false
        }
        if attachments.contains(where: { !ImageProcessor.canDecode($0.imageData) }) {
            errorMessage = "An image can't be read. Remove it and try again."
            return false
        }
        do {
            let service = try await makeService(post.target, store)
            let item = try await service.reply(to: post, text: text, images: attachments,
                                               visibility: visibility)
            didPost = true
            postedURL = item.url.flatMap(URL.init(string:))
            // Refresh the panel for this platform so the reply shows up.
            NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                            userInfo: [crossPostTargetsKey: Set([post.target])])
            return true
        } catch {
            errorMessage = error.userMessage
            return false
        }
    }
}
