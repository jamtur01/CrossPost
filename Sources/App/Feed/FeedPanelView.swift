import SwiftUI
import AppKit

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State private var replyTarget: FeedPost?
    @State private var routes: [FeedRoute] = []

    private var accent: Color { model.target.accent }
    private static let topAnchor = "feed-top"

    // Messages is only available where the platform supports DMs (Bluesky for now).
    private var availableKinds: [FeedKind] {
        model.target == .bluesky ? FeedKind.allCases : [.home, .notifications]
    }

    var body: some View {
        VStack(spacing: 0) {
            if routes.isEmpty { platformHeader } else { navHeader }
            if routes.isEmpty {
                timeline
            } else {
                // Identity per route so a profile→profile (or thread→thread) push
                // re-creates the view and reloads, instead of reusing stale state.
                routeContent.id(routes.last?.id)
            }
        }
        // Transient errors (failed refresh, like, follow, …) float as a toast over
        // the content so they never shift the layout; they auto-dismiss or tap away.
        .overlay(alignment: .bottom) {
            if let actionError = model.actionError {
                errorBanner(actionError)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.actionError)
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $replyTarget) { post in
            ReplySheet(model: ReplyModel(post: post, store: store)) { replyTarget = nil }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .crossPostCredentialsChanged)) { note in
            if let targets = note.userInfo?[crossPostTargetsKey] as? Set<PostTarget>,
               targets.contains(model.target) {
                routes.removeAll()
                model.start()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .crossPostDidPost)) { note in
            if let targets = note.userInfo?[crossPostTargetsKey] as? Set<PostTarget>,
               targets.contains(model.target) {
                model.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Returning to the app catches the feed and unread badge up at once —
            // important for Bluesky, which has no live stream to drive updates while away.
            model.wake()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAllFeeds)) { _ in
            model.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchFeedKind)) { note in
            // Switch this column's tab only if it offers that kind (Mastodon has no
            // Messages), and pop any in-place navigation so the feed is visible.
            guard let kind = note.userInfo?[feedKindKey] as? FeedKind,
                  availableKinds.contains(kind) else { return }
            routes.removeAll()
            model.switchTo(kind)
        }
    }

    // MARK: Headers

    private var platformHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: model.target.glyph)
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                Text(model.target.displayName).font(Theme.columnTitle)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small).scaleEffect(0.8) }
                headerIcon("magnifyingglass", help: "Search") { routes.append(.search) }
                savedMenu
                headerIcon("person.crop.circle", help: "My profile") { routes.append(.profile(myRef)) }
                headerIcon("arrow.clockwise", help: "Refresh") { model.refresh() }
            }

            HStack(spacing: 8) {
                Picker("Feed", selection: Binding(get: { model.kind }, set: { model.switchTo($0) })) {
                    ForEach(availableKinds) { kind in Text(kind.title).tag(kind) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .tint(accent)
                .fixedSize()
                if model.unreadCount > 0 && model.kind != .notifications {
                    Text(model.unreadCount > 99 ? "99+" : "\(model.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(.red))
                }
                Spacer()
            }
        }
        .padding(.horizontal, Theme.headerPaddingH).padding(.top, 10).padding(.bottom, 9)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Bookmarks (Mastodon only) and Likes for the signed-in user.
    private var savedMenu: some View {
        Menu {
            if model.target == .mastodon {
                Button { routes.append(.saved(.bookmarks)) } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
            }
            Button { routes.append(.saved(.likes)) } label: {
                Label("Likes", systemImage: "heart")
            }
        } label: {
            Image(systemName: "bookmark").font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Saved posts")
    }

    private func headerIcon(_ symbol: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var navHeader: some View {
        HStack(spacing: 8) {
            Button { _ = routes.popLast() } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless).foregroundStyle(accent).help("Back")
            Text(navTitle).font(Theme.columnTitle).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Theme.headerPaddingH).padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var navTitle: String {
        switch routes.last {
        case .thread: return "Thread"
        case .profile(let ref): return ref.name
        case .profileList(let ref): return ref.title
        case .conversation(let convo): return convo.otherName
        case .saved(let kind): return kind.title
        case .search: return "Search"
        case .none: return ""
        }
    }

    private var myRef: ProfileRef {
        let handle = model.target == .mastodon ? store.mastodonUsername : store.blueskyHandle
        return ProfileRef(id: handle, handle: "@\(handle)", name: "My Profile", avatar: nil, isMe: true)
    }

    // MARK: Content

    @ViewBuilder
    private var routeContent: some View {
        switch routes.last {
        case .thread(let post):
            ThreadView(panel: model, store: store, post: post) { routes.append($0) }
        case .profile(let ref):
            ProfileView(panel: model, store: store, ref: ref) { routes.append($0) }
        case .profileList(let ref):
            ProfileListView(panel: model, ref: ref) { routes.append($0) }
        case .conversation(let convo):
            ConversationView(panel: model, conversation: convo) { routes.append($0) }
        case .saved(let kind):
            SavedPostsView(panel: model, store: store, kind: kind) { routes.append($0) }
        case .search:
            SearchView(panel: model, store: store) { routes.append($0) }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if model.needsCredentials {
            connectState
        } else if model.kind == .notifications {
            NotificationsListView(model: model, push: { routes.append($0) },
                                  onReply: { replyTarget = $0 })
        } else if model.kind == .messages {
            MessagesListView(model: model) { routes.append($0) }
        } else if let error = model.errorMessage, model.posts.isEmpty {
            emptyState(error, systemImage: "exclamationmark.triangle")
        } else if model.posts.isEmpty && model.isLoading {
            skeletonList
        } else if model.posts.isEmpty {
            emptyState("No posts yet.", systemImage: "text.bubble")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: 0).id(Self.topAnchor)
                        ForEach(model.posts) { post in
                            FeedPostView(
                                post: post,
                                accent: accent,
                                onReply: { replyTarget = post },
                                onLike: { model.toggleLike(post) },
                                onRepost: { model.toggleRepost(post) },
                                onOpen: { model.openInBrowser(post) },
                                onOpenProfile: { routes.append(.profile(post.profileRef())) },
                                onOpenURL: { model.openLink($0) { routes.append($0) } },
                                isMine: model.isMine(post),
                                onBookmark: { model.setBookmarked(!post.isBookmarked, on: post) },
                                onDelete: { model.deletePost(post) },
                                onPin: { model.setPinned(!post.isPinned, on: post) },
                                onLikedBy: { routes.append(.profileList(ProfileListRef(kind: .likedBy, post: post))) },
                                onRepostedBy: { routes.append(.profileList(ProfileListRef(kind: .repostedBy, post: post))) },
                                onShowParent: post.isReply ? { routes.append(.thread(post)) } : nil,
                                onOpenDetail: { routes.append(.thread(post)) },
                                onReport: model.isMine(post) ? nil : { reason, comment in
                                    try await model.report(post: post, reason: reason, comment: comment)
                                },
                                onQuote: { text, visibility in
                                    _ = try await model.quote(post: post, text: text, visibility: visibility)
                                },
                                onEdit: postEditActions(for: post, model),
                                onCopyLink: { model.copyLink(post) })
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.scrollToTopToken) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.topAnchor, anchor: .top)
                    }
                }
            }
        }
    }

    /// First-load placeholder: a short column of shimmering rows, so the pane reads
    /// as content arriving rather than a lone spinner on emptiness.
    private var skeletonList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { _ in
                    SkeletonRow()
                    Divider().opacity(0.5)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .contentShape(Capsule())
        .onTapGesture { model.dismissActionError() }
        .help("Dismiss")
    }

    private var connectState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Connect \(model.target.displayName) in Settings")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        EmptyStateView(text: text, systemImage: systemImage)
    }
}
