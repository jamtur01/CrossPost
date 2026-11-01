import SwiftUI

extension FeedPanelView {
    // MARK: Content

    @ViewBuilder
    func routeContent(for route: FeedRoute) -> some View {
        switch route {
        case let .thread(post):
            ThreadView(panel: model, store: store, post: post, push: pushRoute)
        case let .profile(ref):
            ProfileView(panel: model, store: store, ref: ref, push: pushRoute)
        case let .profileList(ref):
            ProfileListView(panel: model, ref: ref, push: pushRoute)
        case let .conversation(convo):
            ConversationView(panel: model, conversation: convo, push: pushRoute)
        case let .saved(kind):
            SavedPostsView(
                panel: model,
                store: store,
                kind: kind,
                push: pushRoute
            )
        case .search:
            SearchView(panel: model, store: store, push: pushRoute)
        }
    }

    @ViewBuilder
    var timeline: some View {
        if model.needsCredentials {
            connectState
        } else if model.kind == .notifications {
            NotificationsListView(
                model: model,
                push: pushRoute,
                onReply: { replyTarget = $0 }
            )
        } else if model.kind == .messages {
            MessagesListView(model: model, push: pushRoute)
        } else if model.posts.isEmpty, model.isLoading {
            // Loading wins over a previous error so Try Again visibly retries.
            skeletonList
        } else if let error = model.errorMessage, model.posts.isEmpty {
            ErrorStateView(message: error) { model.refresh() }
        } else if model.posts.isEmpty {
            emptyState("No posts yet.", systemImage: "text.bubble")
        } else {
            homeList
        }
    }

    /// SwiftUI's scroll view keeps the rows on screen in place when posts arrive above
    /// them, so the reading position holds on its own. No `scrollPosition(id:)` binding:
    /// keyboard paging and scroll-to-top move the list without updating it, and the
    /// next arrival then jumps the list back to the stale post.
    private var homeList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topAnchor)
                    ForEach(model.posts) { post in
                        FeedRow(
                            post: post,
                            host: model,
                            panel: model,
                            accent: accent,
                            push: pushRoute,
                            onReply: { replyTarget = $0 }
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollContentBackground(.hidden)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { visible in
                let visible = Set(visible)
                homeTopPostID = model.posts.first { visible.contains($0.id) }?.id
                reportHomeScroll()
            }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < 1 } action: {
                homeIsAtTop = $1
                reportHomeScroll()
            }
            .feedKeyboardNavigation(posts: model.posts, hosts: [model], reply: { replyTarget = $0 },
                                    open: { pushRoute(.thread($0)) })
            .onChange(of: model.posts.first?.id) {
                // At the top, arrivals show in place rather than landing just above it.
                if homeIsAtTop {
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
            .onChange(of: model.scrollToTopToken) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
            .overlay(alignment: .top) { newPostsPill }
            .onChange(of: model.newPostCount > 0) { _, appeared in
                guard appeared else { return }
                AccessibilityNotification.Announcement(NewPostsPill.title(model.newPostCount)).post()
            }
        }
    }

    /// Animated on its own, so the rows that arrive with it keep their place.
    private var newPostsPill: some View {
        ZStack {
            if model.newPostCount > 0 {
                NewPostsPill(count: model.newPostCount, target: model.target) { model.scrollToTop() }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
                   value: model.newPostCount > 0)
    }

    private func reportHomeScroll() {
        model.homeScrolled(to: homeIsAtTop ? nil : homeTopPostID)
    }

    /// First-load placeholder: a short column of highlighted rows, so the pane
    /// reads as content arriving rather than a lone spinner on emptiness.
    private var skeletonList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0 ..< 7, id: \.self) { _ in
                    SkeletonRow()
                    Divider().opacity(0.5)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
    }

    func errorBanner(_ text: String) -> some View {
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
                .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75))
        )
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
            .tint(model.target.fillAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        EmptyStateView(text: text, systemImage: systemImage)
    }

    var navTitle: String {
        switch routes.last?.route {
        case .thread: "Thread"
        case let .profile(ref): ref.name
        case let .profileList(ref): ref.title
        case let .conversation(convo): convo.otherName
        case let .saved(kind): kind.title
        case .search: "Search"
        case .none: ""
        }
    }

    var myRef: ProfileRef {
        let handle = model.target == .mastodon ? store.mastodonUsername : store.blueskyHandle
        return ProfileRef(
            id: handle,
            handle: "@\(handle)",
            name: "My Profile",
            avatar: nil,
            isMe: true
        )
    }
}
