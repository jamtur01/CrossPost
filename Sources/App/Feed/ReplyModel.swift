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
        // Replies start by mentioning the author (Mastodon needs it in the text;
        // Bluesky turns "@handle" into a mention facet automatically).
        self.text = post.authorHandle + " "
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
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
