import SwiftUI

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State private var replyTarget: FeedPost?
    @State private var routes: [FeedRoute] = []

    private var accent: Color { model.target.accent }

    var body: some View {
        VStack(spacing: 0) {
            if routes.isEmpty {
                platformHeader
                if let actionError = model.actionError {
                    errorBanner(actionError)
                }
                if let refreshError = model.errorMessage, !model.posts.isEmpty {
                    errorBanner(refreshError)
                }
                timeline
            } else {
                navHeader
                routeContent
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .refreshAllFeeds)) { _ in
            model.refresh()
        }
    }

    // MARK: Headers

    private var platformHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.target.glyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(model.target.displayName).font(.headline)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button { routes.append(.profile(myRef)) } label: {
                    Image(systemName: "person.crop.circle").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless).foregroundStyle(accent).help("My profile")
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderless).foregroundStyle(accent).help("Refresh")
            }

            Picker("Feed", selection: Binding(get: { model.kind }, set: { model.switchTo($0) })) {
                ForEach(FeedKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .tint(accent)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
        .background(headerBackground)
        .overlay(alignment: .bottom) { accentRule }
    }

    private var navHeader: some View {
        HStack(spacing: 8) {
            Button { _ = routes.popLast() } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless).foregroundStyle(accent).help("Back")
            Text(navTitle).font(.headline).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 11)
        .background(headerBackground)
        .overlay(alignment: .bottom) { accentRule }
    }

    private var headerBackground: some View {
        ZStack {
            Rectangle().fill(.bar)
            accent.opacity(0.12)
        }
    }

    private var accentRule: some View {
        Rectangle().fill(accent.opacity(0.35)).frame(height: 1)
    }

    private var navTitle: String {
        switch routes.last {
        case .thread: return "Thread"
        case .profile(let ref): return ref.name
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
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if model.needsCredentials {
            connectState
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
                            onOpenProfile: { routes.append(.profile(post.profileRef())) },
                            onOpenURL: { model.open($0) },
                            onShowParent: post.isReply ? { routes.append(.thread(post)) } : nil,
                            onOpenDetail: { routes.append(.thread(post)) })
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.08))
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
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}
