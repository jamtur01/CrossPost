import SwiftUI

/// The notifications feed: likes, reposts, follows, mentions, replies, quotes.
struct NotificationsListView: View {
    let model: FeedPanelModel
    let push: (FeedRoute) -> Void
    let onReply: (FeedPost) -> Void

    private var accent: Color { model.target.accent }

    var body: some View {
        if model.notifications.isEmpty && model.isLoading {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if model.notifications.isEmpty {
            EmptyStateView(text: "No notifications yet", systemImage: "bell")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.notifications) { notification in
                        NotificationRow(notification: notification, accent: accent,
                                        model: model, push: push, onReply: onReply)
                        Divider().opacity(0.5)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct NotificationRow: View {
    let notification: FeedNotification
    let accent: Color
    let model: FeedPanelModel
    let push: (FeedRoute) -> Void
    let onReply: (FeedPost) -> Void

    @State private var hovering = false
    // Optimistic like/repost state for the referenced post (nil → use the
    // notification's snapshot). Held so repeated toggles keep the record URIs.
    @State private var post: FeedPost?
    @State private var mutating = false
    @State private var followWorking = false

    private var livePost: FeedPost? { post ?? notification.post }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    // Avatar + name open the actor's profile; the rest opens the post.
                    Button(action: openProfile) {
                        HStack(spacing: 7) {
                            AvatarView(url: notification.avatarURL, size: 26, ring: false)

                            Text(notification.actorName).font(Theme.name).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(actionText).font(Theme.handle).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    relativeTimestamp(notification.date)
                }

                if let post = livePost, !post.text.characters.isEmpty {
                    PostBody(text: post.text, accent: accent, cacheKey: post.id,
                             color: bodyIsPrimary ? AnyShapeStyle(.primary)
                                                  : AnyShapeStyle(.secondary),
                             lineLimit: 3,
                             onOpenURL: { model.openLink($0, push: push) })
                }

                actionBar
            }
        }
        .padding(.horizontal, Theme.rowPaddingH).padding(.vertical, 10)
        .background(hovering ? Theme.hoverFill : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: openPost)
        .onHover { hovering = $0 }
        // Drop the optimistic copy when the underlying snapshot refreshes, so
        // server truth wins instead of a stale local like/repost shadowing it.
        .onChange(of: notification.post) { post = nil }
    }

    private var actorRef: ProfileRef {
        ProfileRef(id: notification.actorID, handle: notification.actorHandle,
                   name: notification.actorName, avatar: notification.avatarURL)
    }

    private func openProfile() { push(.profile(actorRef)) }

    private func openPost() {
        if let post = livePost { push(.thread(post)) } else { push(.profile(actorRef)) }
    }

    // MARK: Actions

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 18) {
            if let post = livePost {
                postActionButton("arrowshape.turn.up.left", tint: accent, help: "Reply",
                                compact: true) { onReply(post) }
                postActionButton("arrow.2.squarepath", active: post.isReposted, tint: .green,
                                 help: post.isReposted ? "Undo repost" : "Repost",
                                 compact: true, action: toggleRepost)
                postActionButton(post.isLiked ? "heart.fill" : "heart", active: post.isLiked,
                                 tint: .pink, help: post.isLiked ? "Unlike" : "Like",
                                 compact: true, action: toggleLike)
            }
            followButton
            Spacer(minLength: 0)
        }
        .padding(.top, 3)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var followButton: some View {
        // Real follow state, batch-resolved by the model when the page loaded —
        // someone you already follow shows "Following" instead of an actionable
        // "Follow" that would be a no-op.
        let isFollowing = model.isFollowing(notification.actorID)
        Button { Task { await follow() } } label: {
            HStack(spacing: 3) {
                Image(systemName: isFollowing ? "checkmark" : "person.badge.plus")
                Text(isFollowing ? "Following" : "Follow")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isFollowing ? .secondary : accent)
            .contentShape(Rectangle())
        }
        .help(isFollowing ? "Following \(notification.actorName)" : "Follow \(notification.actorName)")
        .disabled(followWorking || isFollowing)
    }

    private func toggleLike() {
        guard !mutating, var optimistic = livePost else { return }
        mutating = true
        let original = optimistic
        optimistic.isLiked.toggle()
        optimistic.likeCount = max(0, optimistic.likeCount + (optimistic.isLiked ? 1 : -1))
        post = optimistic
        Task {
            defer { mutating = false }
            do { post = try await model.serviceSetLiked(optimistic.isLiked, on: optimistic) }
            catch { post = original; model.reportActionError(error.userMessage) }
        }
    }

    private func toggleRepost() {
        guard !mutating, var optimistic = livePost else { return }
        mutating = true
        let original = optimistic
        optimistic.isReposted.toggle()
        optimistic.repostCount = max(0, optimistic.repostCount + (optimistic.isReposted ? 1 : -1))
        post = optimistic
        Task {
            defer { mutating = false }
            do { post = try await model.serviceSetReposted(optimistic.isReposted, on: optimistic) }
            catch { post = original; model.reportActionError(error.userMessage) }
        }
    }

    private func follow() async {
        guard !followWorking, !model.isFollowing(notification.actorID) else { return }
        followWorking = true
        defer { followWorking = false }
        await model.follow(actorID: notification.actorID)
    }

    private var icon: String {
        switch notification.kind {
        case .like: return "heart.fill"
        case .repost: return "arrow.2.squarepath"
        case .follow: return "person.fill.badge.plus"
        case .mention: return "at"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .quote: return "quote.bubble.fill"
        case .poll: return "chart.bar.fill"
        case .other: return "bell.fill"
        }
    }

    // Mentions, replies, and quotes carry text directed at the user, so render
    // it in the primary color. For likes/reposts/polls the body is the user's
    // own post shown only as context, which stays secondary.
    private var bodyIsPrimary: Bool {
        switch notification.kind {
        case .mention, .reply, .quote: return true
        case .like, .repost, .follow, .poll, .other: return false
        }
    }

    private var tint: Color {
        switch notification.kind {
        case .like: return .pink
        case .repost: return .green
        default: return accent
        }
    }

    private var actionText: String {
        switch notification.kind {
        case .like: return "liked your post"
        case .repost: return "reposted your post"
        case .follow: return "followed you"
        case .mention: return "mentioned you"
        case .reply: return "replied"
        case .quote: return "quoted your post"
        case .poll: return "a poll ended"
        case .other: return ""
        }
    }
}
