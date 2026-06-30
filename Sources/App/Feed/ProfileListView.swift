import SwiftUI

/// A scrollable list of accounts (followers or following), each row tappable to
/// open that profile.
struct ProfileListView: View {
    let panel: FeedPanelModel
    let ref: ProfileListRef
    let push: (FeedRoute) -> Void

    @State private var profiles: [Profile] = []
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { Divider().opacity(0.5) }
                    row(profile)
                }
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if let loadError, profiles.isEmpty {
                    ErrorStateView(message: loadError, fills: false) { Task { await load() } }
                } else if profiles.isEmpty {
                    EmptyStateView(text: "No one here yet", systemImage: "person.2", fills: false)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task { await load() }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            switch ref.kind {
            case .followers: profiles = try await panel.followers(of: ref.accountID)
            case .following: profiles = try await panel.following(of: ref.accountID)
            case .likedBy: if let post = ref.post { profiles = try await panel.likedBy(post) }
            case .repostedBy: if let post = ref.post { profiles = try await panel.repostedBy(post) }
            }
        } catch {
            loadError = error.userMessage
        }
        loading = false
    }

    private func row(_ profile: Profile) -> some View {
        Button {
            push(.profile(ProfileRef(id: profile.id, handle: profile.handle,
                                     name: profile.name, avatar: profile.avatarURL)))
        } label: {
            HStack(alignment: .top, spacing: Theme.gutter) {
                AvatarView(url: profile.avatarURL, size: Theme.avatarSmall)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(Theme.name).lineLimit(1)
                    Text(profile.handle).font(Theme.handle).foregroundStyle(.secondary).lineLimit(1)
                    if !profile.bio.characters.isEmpty {
                        Text(profile.bio).font(Theme.meta).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.rowPaddingH).padding(.vertical, 10)
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .buttonStyle(.plain)
    }
}
