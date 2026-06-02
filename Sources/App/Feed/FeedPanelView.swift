import SwiftUI

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State private var replyTarget: FeedPost?
    @State private var parentOf: FeedPost?

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

            if let actionError = model.actionError {
                Text(actionError)
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
            }

            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $replyTarget) { post in
            ReplySheet(model: ReplyModel(post: post, store: store)) { replyTarget = nil }
        }
        .sheet(item: $parentOf) { post in
            ParentSheet(
                fetch: { await model.parent(of: post) },
                onOpen: { model.openInBrowser($0) },
                onClose: { parentOf = nil })
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
                            onOpen: { model.openInBrowser(post) },
                            onShowParent: post.isReply ? { parentOf = post } : nil)
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
