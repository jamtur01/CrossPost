import SwiftUI

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State private var replyTarget: FeedPost?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.target.displayName).font(.headline)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Picker("Feed", selection: Binding(get: { model.kind }, set: { model.switchTo($0) })) {
                ForEach(FeedKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $replyTarget) { post in
            ReplySheet(model: ReplyModel(post: post, store: store)) { replyTarget = nil }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        // Pick up credentials saved in Settings after launch (the URL/handle change republishes).
        .onChange(of: store.mastodonInstanceURL) { if model.target == .mastodon { model.start() } }
        .onChange(of: store.blueskyHandle) { if model.target == .bluesky { model.start() } }
        // Refresh after a cross-post lands on this panel's platform.
        .onReceive(NotificationCenter.default.publisher(for: .crossPostDidPost)) { note in
            if let targets = note.userInfo?[crossPostTargetsKey] as? Set<PostTarget>,
               targets.contains(model.target) {
                model.refresh()
            }
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
                LazyVStack(spacing: 8) {
                    ForEach(model.posts) { post in
                        FeedPostView(
                            post: post,
                            onReply: { replyTarget = post },
                            onLike: { model.toggleLike(post) },
                            onRepost: { model.toggleRepost(post) },
                            onOpen: { model.openInBrowser(post) })
                    }
                }
                .padding(10)
            }
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
