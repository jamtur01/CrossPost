import AppKit
import SwiftUI

/// A profile: banner, avatar, bio, counts, and the user's recent posts.
struct ProfileView: View {
    let panel: FeedPanelModel
    let store: AccountStore
    let ref: ProfileRef
    let push: (FeedRoute) -> Void

    /// Optional, matching FeedPostView: contexts without a lightbox installed just
    /// leave the banner/avatar non-poppable rather than crashing on first tap.
    @Environment(ImageLightbox.self) private var lightbox: ImageLightbox?

    @State var profile: Profile?
    @State var list: PostList
    @State var pinnedList: PostList
    @State private var replyTarget: FeedPost?
    @State var partialLoad = ProfilePartialLoadState()
    @State var isUpdatingRelationship = false
    @State var relationshipTask: Task<Void, Never>?
    @State var relationshipGeneration: UInt = 0
    @State var loading = true
    @State var loadError: String?
    @State var postsLoadError: String?
    @State var reportingAccount = false
    @State var loadToken = 0
    @State var relationshipLoadToken = 0
    @State var pinnedLoadToken = 0

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
                if !ref.isMe, let error = partialLoad.relationshipError {
                    partialErrorRow("Relationship", message: error) {
                        relationshipLoadToken += 1
                    }
                }
                Divider()
                LazyVStack(spacing: 0) {
                    if !pinnedList.posts.isEmpty
                        || partialLoad.isPinnedLoading
                        || partialLoad.pinnedError != nil {
                        pinnedHeader
                        ForEach(pinnedList.posts) { row in
                            postRow(row, in: pinnedList)
                        }
                        if partialLoad.isPinnedLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else if let error = partialLoad.pinnedError {
                            partialErrorRow("Pinned posts", message: error) {
                                pinnedLoadToken += 1
                            }
                        }
                    }
                    ForEach(feedRows) { row in
                        postRow(row, in: list)
                    }
                }
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if let loadError {
                    ErrorStateView(message: loadError, fills: false) { loadToken += 1 }
                } else if let postsLoadError {
                    partialErrorRow("Recent posts", message: postsLoadError) { loadToken += 1 }
                } else if pinnedList.posts.isEmpty
                    && feedRows.isEmpty
                    && partialLoad.pinnedError == nil
                    && !partialLoad.isPinnedLoading {
                    EmptyStateView(text: "No posts yet", systemImage: "text.bubble", fills: false)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: loadToken) { await load() }
        .task(id: relationshipLoadToken) { await loadRelationship() }
        .task(id: pinnedLoadToken) { await loadPinnedPosts() }
        .onDisappear {
            list.invalidateOptimisticMutations()
            pinnedList.invalidateOptimisticMutations()
            invalidateRelationshipAction()
        }
        .sheet(isPresented: $reportingAccount) {
            ReportSheet(
                subjectLabel: profile?.handle ?? ref.handle,
                accent: accent,
                submit: { reason, comment in
                    try await panel.report(
                        accountID: accountID,
                        reason: reason,
                        comment: comment
                    )
                },
                onClose: { reportingAccount = false }
            )
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
            .onTapGesture {
                if let url = profile?.bannerURL {
                    lightbox?.present(url)
                }
            }
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
                    .overlay(
                        Circle().strokeBorder(
                            Color(nsColor: .textBackgroundColor),
                            lineWidth: 4
                        )
                    )
                    .overlay(Circle().strokeBorder(accent.opacity(0.4), lineWidth: 1.5))
                    .offset(y: -34)
                    .padding(.bottom, -34)
                    .contentShape(Circle())
                    .onTapGesture { popOutAvatar() }
                    .pointingHandCursor(enabled: lightbox != nil)
                    .help("View profile photo")

                    Spacer()

                    if !ref.isMe {
                        relationshipControls
                    }
                    if let url = profile?.webURL {
                        Button { panel.open(url) } label: {
                            Image(systemName: "safari").font(.system(size: 14))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(accent)
                        .help("Open profile in browser")
                    }
                }

                profileIdentityAndStats
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var profileIdentityAndStats: some View {
        Text(profile?.name ?? ref.name)
            .font(.title3.weight(.bold))
            .lineLimit(1)
        HStack(spacing: 6) {
            Text(profile?.handle ?? ref.handle)
                .font(Theme.meta)
                .foregroundStyle(.secondary)
            if partialLoad.relationship?.isFollowedBy == true {
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
                    panel.openLink(url, push: push)
                    return .handled
                })
        }

        if let profile {
            HStack(spacing: 18) {
                stat(profile.posts, "Posts")
                Button {
                    push(
                        .profileList(
                            ProfileListRef(
                                kind: .following,
                                accountID: profile.id
                            )
                        )
                    )
                } label: { stat(profile.following, "Following") }
                    .buttonStyle(.plain)
                Button {
                    push(
                        .profileList(
                            ProfileListRef(
                                kind: .followers,
                                accountID: profile.id
                            )
                        )
                    )
                } label: { stat(profile.followers, "Followers") }
                    .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
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
}
