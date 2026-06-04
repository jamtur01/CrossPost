import SwiftUI

/// A larger pop-out of a single post, opened by clicking it in the timeline.
/// Reads the post live from the panel model so likes/reposts stay in sync.
struct PostDetailSheet: View {
    let model: FeedPanelModel
    let store: AccountStore
    let postID: String
    let onClose: () -> Void

    @State private var replyTarget: FeedPost?
    @State private var parentOf: FeedPost?

    private var post: FeedPost? { model.posts.first { $0.id == postID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(model.target.accent).frame(width: 9, height: 9)
                Text("Post").font(.headline)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.bar)

            Divider()

            ScrollView {
                if let post {
                    FeedPostView(
                        post: post,
                        accent: model.target.accent,
                        onReply: { replyTarget = post },
                        onLike: { model.toggleLike(post) },
                        onRepost: { model.toggleRepost(post) },
                        onOpen: { model.openInBrowser(post) },
                        onShowParent: post.isReply ? { parentOf = post } : nil,
                        inTimeline: false,
                        expanded: true)
                        .padding(16)
                } else {
                    Label("This post is no longer available.", systemImage: "questionmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .frame(width: 500, height: 580)
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
        .sheet(item: $parentOf) { target in
            ParentSheet(
                fetch: { await model.parent(of: target) },
                onOpen: { model.openInBrowser($0) },
                onClose: { parentOf = nil })
        }
    }
}
