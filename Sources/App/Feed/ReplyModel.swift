import Foundation
import SwiftUI

@MainActor
@Observable
final class ReplyModel {
    let post: FeedPost
    var text: String = ""
    var attachments: [Attachment] = []
    var isSending = false
    var errorMessage: String?
    var postedURL: String?

    private let store: AccountStore

    init(post: FeedPost, store: AccountStore) {
        self.post = post
        self.store = store

        // Prefill the reply with everyone it should mention: the author plus anyone
        // the parent post mentioned, de-duplicated and excluding your own handle.
        // Mastodon needs these in the text to mention/notify; Bluesky turns each
        // "@handle" into a mention facet.
        let ownHandle: String
        switch post.target {
        case .mastodon: ownHandle = store.mastodonUsername.isEmpty ? "" : "@\(store.mastodonUsername)"
        case .bluesky: ownHandle = store.blueskyHandle.isEmpty ? "" : "@\(store.blueskyHandle)"
        }
        var seen: Set<String> = []
        var mentions: [String] = []
        for handle in [post.authorHandle] + post.mentionHandles {
            let trimmed = handle.trimmingCharacters(in: .whitespaces)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, key != ownHandle.lowercased(), seen.insert(key).inserted else { continue }
            mentions.append(trimmed)
        }
        self.text = mentions.isEmpty ? "" : mentions.joined(separator: " ") + " "
    }

    var canSend: Bool { !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let service = try await FeedServiceFactory.make(for: post.target, store: store)
            let item = try await service.reply(to: post, text: text, images: attachments)
            postedURL = item.url ?? "Sent."
            // Refresh the panel for this platform so the reply shows up.
            NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                            userInfo: [crossPostTargetsKey: Set([post.target])])
        } catch {
            errorMessage = error.userMessage
        }
    }
}
