import SwiftUI
import AppKit

/// A profile: banner, avatar, bio, counts, and the user's recent posts.
struct ProfileView: View {
    let panel: FeedPanelModel
    let store: AccountStore
    let ref: ProfileRef
    let push: (FeedRoute) -> Void

    @Environment(ImageLightbox.self) private var lightbox

    @State private var profile: Profile?
    @State private var list: PostList
    @State private var pinnedList: PostList
    @State private var replyTarget: FeedPost?
    @State private var relationship = AccountRelationship()
    @State private var updatingRelationship = false
    @State private var loading = true
    @State private var reportingAccount = false

    private var accent: Color { panel.target.accent }
    private var accountID: String { profile?.id ?? ref.id }

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
                    ForEach(list.posts) { row in
                        postRow(row, in: list)
                    }
                }
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            profile = ref.isMe ? await panel.myProfile() : await panel.profile(id: ref.id)
            let id = profile?.id ?? ref.id
            // Both calls only need the resolved id, so they run concurrently.
            async let posts = panel.authorPosts(id: id)
            async let pins = panel.pinnedPosts(id: id)
            if !ref.isMe { relationship = await panel.relationship(with: id) }
            pinnedList.posts = await pins
            list.posts = await posts
            loading = false
        }
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
            AsyncImage(url: profile?.bannerURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [accent.opacity(0.5), accent.opacity(0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if let url = profile?.bannerURL { lightbox.present(url) } }
            .onHover { hovering in
                guard profile?.bannerURL != nil else { return }
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help(profile?.bannerURL != nil ? "View banner" : "")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom) {
                    AsyncImage(url: profile?.avatarURL ?? ref.avatar) { img in
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
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
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

    @ViewBuilder
    private func postRow(_ row: FeedPost, in list: PostList) -> some View {
        FeedPostView(
            post: row,
            accent: accent,
            onReply: { replyTarget = row },
            onLike: { list.toggleLike(row) },
            onRepost: { list.toggleRepost(row) },
            onOpen: { panel.openInBrowser(row) },
            onOpenProfile: { push(.profile(row.profileRef())) },
            onOpenURL: { panel.openLink($0, push: push) },
            isMine: panel.isMine(row),
            onBookmark: { list.setBookmarked(!row.isBookmarked, row) },
            onDelete: { list.delete(row) },
            onPin: { list.setPinned(!row.isPinned, row) },
            onLikedBy: { push(.profileList(ProfileListRef(kind: .likedBy, post: row))) },
            onRepostedBy: { push(.profileList(ProfileListRef(kind: .repostedBy, post: row))) },
            onShowParent: row.isReply ? { push(.thread(row)) } : nil,
            onOpenDetail: { push(.thread(row)) },
            onReport: panel.isMine(row) ? nil : { reason, comment in
                try await panel.report(post: row, reason: reason, comment: comment)
            },
            onQuote: { text, visibility in
                _ = try await panel.quote(post: row, text: text, visibility: visibility)
            },
            onEdit: postEditActions(for: row, panel),
            onCopyLink: { panel.copyLink(row) })
    }

    private var pinnedHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill").font(.system(size: 10))
            Text("Pinned").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.top, 8).padding(.bottom, 2)
    }

    private func popOutAvatar() {
        if let url = profile?.avatarURL ?? ref.avatar {
            lightbox.present(url, circular: true)
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
            .disabled(updatingRelationship)

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
        guard !updatingRelationship else { return }
        updatingRelationship = true
        defer { updatingRelationship = false }
        let target = !relationship.isFollowing
        let previous = relationship
        relationship.isFollowing = target
        profile?.followers = max(0, (profile?.followers ?? 0) + (target ? 1 : -1))
        do { relationship = try await panel.setFollowing(target, for: accountID, current: previous) }
        catch {
            relationship = previous
            profile?.followers = max(0, (profile?.followers ?? 0) + (target ? -1 : 1))
            panel.reportActionError(error.userMessage)
        }
    }

    private func toggleMute() async {
        guard !updatingRelationship else { return }
        updatingRelationship = true
        defer { updatingRelationship = false }
        let target = !relationship.isMuting
        let previous = relationship
        relationship.isMuting = target
        do { relationship = try await panel.setMuted(target, for: accountID, current: previous) }
        catch { relationship = previous; panel.reportActionError(error.userMessage) }
    }

    private func toggleBlock() async {
        guard !updatingRelationship else { return }
        updatingRelationship = true
        defer { updatingRelationship = false }
        let target = !relationship.isBlocking
        let previous = relationship
        relationship.isBlocking = target
        do { relationship = try await panel.setBlocked(target, for: accountID, current: previous) }
        catch { relationship = previous; panel.reportActionError(error.userMessage) }
    }
}
