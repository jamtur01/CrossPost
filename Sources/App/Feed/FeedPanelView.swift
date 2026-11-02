import AppKit
import SwiftUI

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State var replyTarget: FeedPost?
    @State var routes: [FeedDestination] = []
    @State private var composingMessage = false
    @State var homeTopPostID: String?
    @State var homeIsAtTop = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var accent: Color {
        model.target.accent
    }

    static let topAnchor = "feed-top"

    var body: some View {
        VStack(spacing: 0) {
            if routes.isEmpty {
                platformHeader
            } else {
                navHeader
            }
            NavigationStack(path: $routes) {
                timeline
                    .environment(\.feedListContext, listContext(isActive: routes.isEmpty, canPop: false))
                    .navigationDestination(for: FeedDestination.self) { destination in
                        routeContent(for: destination.route)
                            .navigationBarBackButtonHidden()
                            .environment(\.feedListContext,
                                         listContext(isActive: destination == routes.last, canPop: true))
                    }
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
        .sheet(isPresented: $composingMessage) {
            NewMessageSheet(panel: model) { convo in
                composingMessage = false
                pushRoute(.conversation(convo))
            } onCancel: {
                composingMessage = false
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: routes) { model.invalidateProfileLinkLookup() }
        .onReceive(
            NotificationCenter.default.publisher(for: .crossPostCredentialsChanged)
        ) { note in
            if note.concerns(model.target) {
                replyTarget = nil
                clearRoutes()
                model.restartAfterCredentialsChange()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .crossPostDidPost)) { note in
            if note.concerns(model.target) {
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
            // Switch this column's tab and pop any in-place navigation so the feed is visible.
            guard let kind = note.userInfo?[feedKindKey] as? FeedKind else { return }
            clearRoutes()
            model.switchTo(kind)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFeedPost)) { note in
            // The composer's Recent Posts opens a sent copy in its own network's column.
            guard let post = note.userInfo?[feedPostKey] as? FeedPost, post.target == model.target else { return }
            pushRoute(.thread(post))
        }
    }

    func pushRoute(_ route: FeedRoute) {
        routes.append(FeedDestination(route: route))
    }

    private func popRoute() {
        _ = routes.popLast()
    }

    private func listContext(isActive: Bool, canPop: Bool) -> FeedListContext {
        let pop: (() -> Void)? = canPop ? { popRoute() } : nil
        return FeedListContext(target: model.target, isActive: isActive, pop: pop)
    }

    private func clearRoutes() {
        routes.removeAll()
    }

    // MARK: Headers

    private var platformHeader: some View {
        HStack(spacing: 4) {
            feedTitleMenu
                .frame(maxWidth: .infinity, alignment: .leading)
            notificationButton
            if model.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                    .frame(width: 14, height: 14)
            }
            if model.kind == .messages {
                headerIcon("square.and.pencil", help: "New Message") {
                    composingMessage = true
                }
            }
            headerIcon("magnifyingglass", help: "Search") {
                pushRoute(.search)
            }
            overflowMenu
        }
        .padding(.horizontal, Theme.headerPaddingH)
        .frame(height: 52)
        .barSurface()
    }

    /// The network leads in the column title so the two columns read apart at a
    /// glance; the current feed sits beneath it as a menu.
    private var feedTitleMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
            networkTitle
            feedKindMenu
        }
    }

    private var feedKindMenu: some View {
        Menu {
            ForEach(FeedKind.allCases) { kind in
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
            HStack(spacing: 3) {
                Text(model.kind.title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(Theme.columnSubtitle)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        // A plain-styled menu so the label keeps the subtitle's color and aligns with
        // the title; the borderless style tints it primary and insets it.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
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
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
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
            Button {
                pushRoute(.saved(.bookmarks))
            } label: {
                Label("Bookmarks", systemImage: "bookmark")
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
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
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
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel(help)
        .help(help)
    }

    private var navHeader: some View {
        HStack(spacing: 8) {
            Button { popRoute() } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless).foregroundStyle(accent).help("Back")
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 1) {
                networkTitle
                Text(navTitle)
                    .font(Theme.columnSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.headerPaddingH)
        .frame(height: 52)
        .barSurface()
    }

    private var networkTitle: some View {
        HStack(spacing: 5) {
            Image(systemName: model.target.glyph)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(model.target.displayName)
                .lineLimit(1)
        }
        .font(Theme.columnTitle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
