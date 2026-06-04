import SwiftUI

/// A pop-out thread view: the focused post (live from the model, with full
/// actions) surrounded by its ancestors above and replies below.
struct PostDetailSheet: View {
    let model: FeedPanelModel
    let store: AccountStore
    let postID: String
    let onClose: () -> Void

    @State private var replyTarget: FeedPost?
    @State private var thread: PostThread?
    @State private var loading = true

    private var accent: Color { model.target.accent }
    private var post: FeedPost? { model.posts.first { $0.id == postID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text("Thread").font(.headline)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(accent.opacity(0.08))
            .background(.bar)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(thread?.ancestors ?? []) { contextRow($0) }

                    if let post {
                        FeedPostView(
                            post: post,
                            accent: accent,
                            onReply: { replyTarget = post },
                            onLike: { model.toggleLike(post) },
                            onRepost: { model.toggleRepost(post) },
                            onOpen: { model.openInBrowser(post) },
                            onOpenProfile: { model.openProfile(post) },
                            onOpenURL: { model.open($0) },
                            inTimeline: false,
                            expanded: true)
                            .padding(16)
                            .background(accent.opacity(0.06))
                    } else {
                        Label("This post is no longer available.", systemImage: "questionmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }

                    ForEach(thread?.descendants ?? []) { contextRow($0) }

                    if loading {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: 540, height: 660)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            if let post { thread = await model.thread(of: post) }
            loading = false
        }
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
    }

    /// A surrounding post: read-only, tap to open in browser.
    private func contextRow(_ row: FeedPost) -> some View {
        FeedPostView(
            post: row,
            accent: accent,
            onOpenProfile: { model.openProfile(row) },
            onOpenURL: { model.open($0) },
            onOpenDetail: { model.openInBrowser(row) },
            showActions: false)
    }
}
