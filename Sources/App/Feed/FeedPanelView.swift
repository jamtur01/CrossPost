import AppKit
import SwiftUI

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State var replyTarget: FeedPost?
    @State var routes: [FeedRoute] = []
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var accent: Color {
        model.target.accent
    }

    static let topAnchor = "feed-top"

    /// Messages is only available where the platform supports DMs (Bluesky for now).
    private var availableKinds: [FeedKind] {
        model.target == .bluesky ? FeedKind.allCases : [.home, .notifications]
    }

    var body: some View {
        VStack(spacing: 0) {
            if routes.isEmpty {
                platformHeader
            } else {
                navHeader
            }
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
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
            value: model.actionError
        )
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $replyTarget) { post in
            ReplySheet(model: ReplyModel(post: post, store: store)) { replyTarget = nil }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(
            NotificationCenter.default.publisher(for: .crossPostCredentialsChanged)
        ) { note in
            if let targets = note.userInfo?[crossPostTargetsKey] as? Set<PostTarget>,
               targets.contains(model.target) {
                replyTarget = nil
                clearRoutes()
                model.restartAfterCredentialsChange()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .crossPostDidPost)) { note in
            if let targets = note.userInfo?[crossPostTargetsKey] as? Set<PostTarget>,
               targets.contains(model.target) {
                model.refresh()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
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
            clearRoutes()
            model.switchTo(kind)
        }
    }

    func pushRoute(_ route: FeedRoute) {
        model.invalidateProfileLinkLookup()
        routes.append(route)
    }

    private func popRoute() {
        model.invalidateProfileLinkLookup()
        _ = routes.popLast()
    }

    private func clearRoutes() {
        model.invalidateProfileLinkLookup()
        routes.removeAll()
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
                pushRoute(.search)
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
                    pushRoute(.saved(.bookmarks))
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
            }
            Button {
                pushRoute(.saved(.likes))
            } label: {
                Label("Likes", systemImage: "heart")
            }
            Button {
                pushRoute(.profile(myRef))
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

    private func headerIcon(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var navHeader: some View {
        HStack(spacing: 8) {
            Button { popRoute() } label: {
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
}
