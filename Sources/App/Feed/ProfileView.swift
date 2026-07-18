import SwiftUI
import AppKit

/// A profile: banner, avatar, bio, counts, and the user's recent posts.
struct ProfileView: View {
    let panel: FeedPanelModel
    let store: AccountStore
    let ref: ProfileRef
    let push: (FeedRoute) -> Void

    // Optional, matching FeedPostView: contexts without a lightbox installed just
    // leave the banner/avatar non-poppable rather than crashing on first tap.
    @Environment(ImageLightbox.self) private var lightbox: ImageLightbox?

    @State private var profile: Profile?
    @State private var list: PostList
    @State private var pinnedList: PostList
    @State private var replyTarget: FeedPost?
    @State private var relationship = AccountRelationship()
    @State private var isUpdatingRelationship = false
    @State private var loading = true
    @State private var loadError: String?
    @State private var reportingAccount = false

    private var accent: Color { panel.target.accent }
    private var accountID: String { profile?.id ?? ref.id }

    /// The author's timeline minus any post already shown in the pinned section,
    /// so the same id is never rendered twice in one container.
    private var feedRows: [FeedPost] {
        let pinnedIDs = Set(pinnedList.posts.map(\.id))
        return list.posts.filter { !pinnedIDs.contains($0.id) }
    }

    init(panel: FeedPanelModel, store: AccountStore, ref: ProfileRef,
         push: @escaping (FeedRoute) -> Void) {
        self.panel = panel
        self.store = store
        self.ref = ref
        self.push = push
        _list = State(initialValue: PostList(panel: panel))
        _pinnedList = State(initialValue: PostList(panel: panel))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerCard
                Divider()
                LazyVStack(spacing: 0) {
                    if !pinnedList.posts.isEmpty {
                        pinnedHeader
                        ForEach(pinnedList.posts) { row in
                            postRow(row, in: pinnedList)
                        }
                    }
                    ForEach(feedRows) { row in
                        postRow(row, in: list)
                    }
                }
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if let loadError, pinnedList.posts.isEmpty && feedRows.isEmpty {
                    ErrorStateView(message: loadError, fills: false) { Task { await load() } }
                } else if pinnedList.posts.isEmpty && feedRows.isEmpty {
                    EmptyStateView(text: "No posts yet", systemImage: "text.bubble", fills: false)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task { await load() }
        .sheet(isPresented: $reportingAccount) {
            ReportSheet(subjectLabel: profile?.handle ?? ref.handle, accent: accent,
                        submit: { reason, comment in
                            try await panel.report(accountID: accountID, reason: reason, comment: comment)
                        }) { reportingAccount = false }
        }
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CachedAsyncImage(url: profile?.bannerURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [accent.opacity(0.5), accent.opacity(0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if let url = profile?.bannerURL { lightbox?.present(url) } }
            .pointingHandCursor(enabled: profile?.bannerURL != nil && lightbox != nil)
            .help(profile?.bannerURL != nil ? "View banner" : "")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom) {
                    CachedAsyncImage(url: profile?.avatarURL ?? ref.avatar) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(.quaternary)
                    }
                    .frame(width: 74, height: 74)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color(nsColor: .textBackgroundColor), lineWidth: 4))
                    .overlay(Circle().strokeBorder(accent.opacity(0.4), lineWidth: 1.5))
                    .offset(y: -34)
                    .padding(.bottom, -34)
                    .contentShape(Circle())
                    .onTapGesture { popOutAvatar() }
                    .pointingHandCursor(enabled: lightbox != nil)
                    .help("View profile photo")

                    Spacer()

                    if !ref.isMe { relationshipControls }
                    if let url = profile?.webURL {
                        Button { panel.open(url) } label: {
                            Image(systemName: "safari").font(.system(size: 14))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(accent)
                        .help("Open profile in browser")
                    }
                }

                Text(profile?.name ?? ref.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(profile?.handle ?? ref.handle)
                        .font(Theme.meta)
                        .foregroundStyle(.secondary)
                    if relationship.isFollowedBy {
                        Text("Follows you")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                            .foregroundStyle(.secondary)
                    }
                }

                if let bio = profile?.bio, !bio.characters.isEmpty {
                    Text(RichText.styled(bio, accent: accent))
                        .font(Theme.content)
                        .tint(accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                        .environment(\.openURL, OpenURLAction { url in
                            panel.openLink(url, push: push); return .handled
                        })
                }

                if let profile {
                    HStack(spacing: 18) {
                        stat(profile.posts, "Posts")
                        Button {
                            push(.profileList(ProfileListRef(kind: .following, accountID: profile.id)))
                        } label: { stat(profile.following, "Following") }
                        .buttonStyle(.plain)
                        Button {
                            push(.profileList(ProfileListRef(kind: .followers, accountID: profile.id)))
                        } label: { stat(profile.followers, "Followers") }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(16)
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            let resolved = ref.isMe ? try await panel.myProfile() : try await panel.profile(id: ref.id)
            profile = resolved
            let id = resolved.id
            // Posts and pins only need the resolved id, so they run concurrently.
            async let posts = panel.authorPosts(id: id)
            async let pins = panel.pinnedPosts(id: id)
            // A relationship failure shouldn't block the profile, so it stays best-effort.
            if !ref.isMe { relationship = await panel.relationship(with: id) }
            // The author timeline is the critical load; pinned posts are best-effort so
            // a hiccup there doesn't blank a profile whose feed loaded fine.
            list.posts = try await posts
            pinnedList.posts = (try? await pins) ?? []
        } catch {
            loadError = error.userMessage
        }
        loading = false
    }

    private func postRow(_ row: FeedPost, in list: PostList) -> some View {
        FeedRow(post: row, host: list, panel: panel, accent: accent,
                push: push, onReply: { replyTarget = $0 })
    }

    private var pinnedHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill").font(.system(size: 10))
            Text("Pinned").font(Theme.sectionHeader)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.top, 8).padding(.bottom, 2)
    }

    private func popOutAvatar() {
        if let url = profile?.avatarURL ?? ref.avatar {
            lightbox?.present(url, circular: true)
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value.formatted(.number.notation(.compactName)))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var relationshipControls: some View {
        HStack(spacing: 8) {
            Group {
                if relationship.isFollowing {
                    Button("Following") { Task { await toggleFollow() } }
                        .buttonStyle(.bordered)
                } else {
                    Button(relationship.isFollowedBy ? "Follow back" : "Follow") {
                        Task { await toggleFollow() }
                    }
                    .buttonStyle(.borderedProminent).tint(accent)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .disabled(isUpdatingRelationship)

            Menu {
                Button(relationship.isMuting ? "Unmute" : "Mute") { Task { await toggleMute() } }
                Button(relationship.isBlocking ? "Unblock" : "Block",
                       role: .destructive) { Task { await toggleBlock() } }
                Divider()
                Button("Report…", role: .destructive) { reportingAccount = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
    }

    private func toggleFollow() async {
        guard !isUpdatingRelationship else { return }
        isUpdatingRelationship = true
        defer { isUpdatingRelationship = false }
        let target = !relationship.isFollowing
        let previous = relationship
        relationship.isFollowing = target
        profile?.followers = max(0, (profile?.followers ?? 0) + (target ? 1 : -1))
        do { relationship = try await panel.setFollowing(target, for: accountID, current: previous) }
        catch {
            relationship = previous
            profile?.followers = max(0, (profile?.followers ?? 0) + (target ? -1 : 1))
            panel.reportError(error.userMessage)
        }
    }

    private func toggleMute() async {
        guard !isUpdatingRelationship else { return }
        isUpdatingRelationship = true
        defer { isUpdatingRelationship = false }
        let target = !relationship.isMuting
        let previous = relationship
        relationship.isMuting = target
        do { relationship = try await panel.setMuted(target, for: accountID, current: previous) }
        catch { relationship = previous; panel.reportError(error.userMessage) }
    }

    private func toggleBlock() async {
        guard !isUpdatingRelationship else { return }
        isUpdatingRelationship = true
        defer { isUpdatingRelationship = false }
        let target = !relationship.isBlocking
        let previous = relationship
        relationship.isBlocking = target
        do { relationship = try await panel.setBlocked(target, for: accountID, current: previous) }
        catch { relationship = previous; panel.reportError(error.userMessage) }
    }
}
