import SwiftUI

extension FeedPanelView {
    // MARK: Content

    @ViewBuilder
    var routeContent: some View {
        switch routes.last {
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
        case .none:
            EmptyView()
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
            .tint(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        EmptyStateView(text: text, systemImage: systemImage)
    }

    var navTitle: String {
        switch routes.last {
        case .thread: return "Thread"
        case let .profile(ref): return ref.name
        case let .profileList(ref): return ref.title
        case let .conversation(convo): return convo.otherName
        case let .saved(kind): return kind.title
        case .search: return "Search"
        case .none: return ""
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
