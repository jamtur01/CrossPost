import SwiftUI

/// A profile: banner, avatar, bio, counts, and the user's recent posts.
struct ProfileView: View {
    let panel: FeedPanelModel
    let store: AccountStore
    let ref: ProfileRef
    let push: (FeedRoute) -> Void

    @State private var profile: Profile?
    @State private var list: PostList
    @State private var replyTarget: FeedPost?
    @State private var loading = true

    private var accent: Color { panel.target.accent }

    init(panel: FeedPanelModel, store: AccountStore, ref: ProfileRef,
         push: @escaping (FeedRoute) -> Void) {
        self.panel = panel
        self.store = store
        self.ref = ref
        self.push = push
        _list = State(initialValue: PostList(panel: panel))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerCard
                Divider()
                LazyVStack(spacing: 0) {
                    ForEach(list.posts) { row in
                        FeedPostView(
                            post: row,
                            accent: accent,
                            onReply: { replyTarget = row },
                            onLike: { list.toggleLike(row) },
                            onRepost: { list.toggleRepost(row) },
                            onOpen: { panel.openInBrowser(row) },
                            onOpenProfile: { push(.profile(row.profileRef())) },
                            onOpenURL: { panel.openLink($0, push: push) },
                            onShowParent: row.isReply ? { push(.thread(row)) } : nil,
                            onOpenDetail: { push(.thread(row)) })
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
            list.posts = await panel.authorPosts(id: profile?.id ?? ref.id)
            loading = false
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

                    Spacer()

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
                Text(profile?.handle ?? ref.handle)
                    .font(Theme.meta)
                    .foregroundStyle(.secondary)

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
                        stat(profile.following, "Following")
                        stat(profile.followers, "Followers")
                    }
                    .padding(.top, 2)
                }
            }
            .padding(16)
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
