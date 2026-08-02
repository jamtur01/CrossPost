import SwiftUI
import AppKit

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State private var replyTarget: FeedPost?
    @State private var routes: [FeedRoute] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: model.actionError)
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
        HStack(spacing: 8) {
            feedTitleMenu
            notificationButton
            Spacer(minLength: 8)
            if model.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.8)
            }
            headerIcon("magnifyingglass", help: "Search") {
                routes.append(.search)
            }
            overflowMenu
        }
        .padding(.horizontal, Theme.headerPaddingH)
        .frame(height: 40)
        .barSurface()
    }

    private var feedTitleMenu: some View {
        Menu {
            ForEach(availableKinds) { kind in
                Button {
                    model.switchTo(kind)
                } label: {
                    if kind == model.kind {
                        Label(feedMenuTitle(for: kind), systemImage: "checkmark")
                    } else {
                        Text(feedMenuTitle(for: kind))
                    }
                }
                .accessibilityLabel(feedMenuAccessibilityLabel(for: kind))
                .accessibilityAddTraits(kind == model.kind ? .isSelected : [])
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.target.glyph)
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                Text(model.kind.title)
                    .font(Theme.columnTitle)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .accessibilityLabel(feedTitleAccessibilityLabel)
        .accessibilityHint("Choose a feed")
        .help("Switch feed")
    }

    private var notificationButton: some View {
        Button {
            model.switchTo(.notifications)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.kind == .notifications ? "bell.fill" : "bell")
                    .font(.system(size: 12, weight: .medium))
                if model.unreadCount > 0 {
                    UnreadBadge(count: model.unreadCount)
                }
            }
            .foregroundStyle(model.kind == .notifications ? accent : .secondary)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel("Notifications")
        .accessibilityValue(
            model.unreadCount > 0
                ? "\(model.unreadCount) unread"
                : "No unread notifications"
        )
        .accessibilityAddTraits(model.kind == .notifications ? .isSelected : [])
        .help(
            model.unreadCount > 0
                ? "Notifications (\(model.unreadCount) unread)"
                : "Notifications"
        )
    }

    private var feedTitleAccessibilityLabel: String {
        let currentFeed = "\(model.target.displayName), current feed: \(model.kind.title)"
        guard model.unreadCount > 0 else { return currentFeed }
        return "\(currentFeed), \(model.unreadCount) unread notifications"
    }

    private func feedMenuTitle(for kind: FeedKind) -> String {
        if kind == .notifications, model.unreadCount > 0 {
            return "\(kind.title) (\(model.unreadCount))"
        }
        return kind.title
    }

    private func feedMenuAccessibilityLabel(for kind: FeedKind) -> String {
        if kind == .notifications, model.unreadCount > 0 {
            return "\(kind.title), \(model.unreadCount) unread"
        }
        return kind.title
    }

    private var overflowMenu: some View {
        Menu {
            if model.target == .mastodon {
                Button {
                    routes.append(.saved(.bookmarks))
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
            }
            Button {
                routes.append(.saved(.likes))
            } label: {
                Label("Likes", systemImage: "heart")
            }
            Button {
                routes.append(.profile(myRef))
            } label: {
                Label("My Profile", systemImage: "person.crop.circle")
            }
            Divider()
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .accessibilityLabel("More feed actions")
        .help("More feed actions")
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
        .padding(.horizontal, Theme.headerPaddingH)
        .frame(height: 40)
        .barSurface()
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
                            FeedRow(post: post, host: model, panel: model, accent: accent,
                                    push: { routes.append($0) }, onReply: { replyTarget = $0 })
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.scrollToTopToken) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
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
