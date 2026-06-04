import SwiftUI

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State private var replyTarget: FeedPost?
    @State private var parentOf: FeedPost?
    @State private var detailPost: FeedPost?

    private var accent: Color { model.target.accent }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 9, height: 9)
                    Text(model.target.displayName)
                        .font(.headline)
                    Spacer()
                    if model.isLoading { ProgressView().controlSize(.small) }
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderless).help("Refresh")
                }

                Picker("Feed", selection: Binding(get: { model.kind }, set: { model.switchTo($0) })) {
                    ForEach(FeedKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .tint(accent)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
            .background(.bar)

            Divider()

            if let actionError = model.actionError {
                Text(actionError)
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
            }

            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $replyTarget) { post in
            ReplySheet(model: ReplyModel(post: post, store: store)) { replyTarget = nil }
        }
        .sheet(item: $parentOf) { post in
            ParentSheet(
                fetch: { await model.parent(of: post) },
                onOpen: { model.openInBrowser($0) },
                onClose: { parentOf = nil })
        }
        .sheet(item: $detailPost) { post in
            PostDetailSheet(model: model, store: store, postID: post.id) { detailPost = nil }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        // Reload when this platform's credentials are (re)saved in Settings.
        .onReceive(NotificationCenter.default.publisher(for: .crossPostCredentialsChanged)) { note in
            if let targets = note.userInfo?[crossPostTargetsKey] as? Set<PostTarget>,
               targets.contains(model.target) {
                model.start()
            }
        }
        // Refresh after a cross-post or reply lands on this platform.
        .onReceive(NotificationCenter.default.publisher(for: .crossPostDidPost)) { note in
            if let targets = note.userInfo?[crossPostTargetsKey] as? Set<PostTarget>,
               targets.contains(model.target) {
                model.refresh()
            }
        }
        // Toolbar "Refresh All".
        .onReceive(NotificationCenter.default.publisher(for: .refreshAllFeeds)) { _ in
            model.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.needsCredentials {
            emptyState(
                "Connect \(model.target.displayName) in Settings (⌘,)",
                systemImage: "person.crop.circle.badge.plus")
        } else if let error = model.errorMessage, model.posts.isEmpty {
            emptyState(error, systemImage: "exclamationmark.triangle")
        } else if model.posts.isEmpty && model.isLoading {
            Spacer(); ProgressView(); Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.posts) { post in
                        FeedPostView(
                            post: post,
                            accent: accent,
                            onReply: { replyTarget = post },
                            onLike: { model.toggleLike(post) },
                            onRepost: { model.toggleRepost(post) },
                            onOpen: { model.openInBrowser(post) },
                            onShowParent: post.isReply ? { parentOf = post } : nil,
                            onOpenDetail: { detailPost = post })
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}
